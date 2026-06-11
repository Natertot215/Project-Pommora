import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderTopics

@MainActor
@Observable
final class TopicManager {
    private(set) var topics: [Topic] = []
    var pendingError: (any Error)?

    private let nexus: Nexus

    /// Current Nexus ID — used by the drag system's cross-window guard.
    var nexusID: String { nexus.id }

    /// Injected by ContentView.constructManagers. Nil until wired; CRUD methods
    /// call it post-commit as a best-effort non-fatal write (filesystem is canonical).
    /// Topics index into `contexts` as tier 2 and Projects as tier 3 via the
    /// `upsertContext(_:)` overloads — without this, the inline tier pickers
    /// (`IndexQuery.entitiesByContextTarget(.contextTier(2/3))`) never see Topics/Projects
    /// created or edited since the last full IndexBuilder rebuild.
    var indexUpdater: IndexUpdater?

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    // MARK: - Load

    func loadAll() async {
        do {
            let topicsDir = NexusPaths.topicsDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(topicsDir)

            var loadedTopics: [Topic] = []

            let topicFolders = try Filesystem.childFolders(of: topicsDir)
            for folder in topicFolders {
                let metaURL = folder.appendingPathComponent("_topic.json")
                guard Filesystem.fileExists(at: metaURL) else { continue }  // skip cosmetic folder
                guard let topic = try? Topic.load(from: metaURL) else { continue }
                loadedTopics.append(topic)
            }

            self.topics = OrderResolver.resolve(
                loadedTopics,
                persistedOrder: readPersistedTopicOrder(),
                titleKeyPath: \Topic.title
            )
            self.pendingError = nil

            // Defensive index sync (quirk #15). Topics (tier 2) arriving outside
            // CRUD (adopted / externally-added / pre-existing folders) must land
            // in the `contexts` table so the tier-2 pickers can surface them.
            // INSERT OR REPLACE is idempotent; failures swallowed (index is
            // regeneratable).
            if let updater = indexUpdater {
                for topic in self.topics {
                    try? updater.upsertContext(topic)
                }
            }
        } catch {
            self.topics = []
            self.pendingError = error
        }
    }

    // MARK: - Topic CRUD

    @discardableResult
    func create(name: String, icon: String?) async throws -> Topic {
        do {
            try TopicValidator.validate(
                title: name,
                existing: topics
            )

            let topic = Topic(
                id: ULID.generate(),
                title: name,
                icon: icon,
                blocks: [],
                modifiedAt: Date()
            )
            let folder = NexusPaths.topicFolderURL(forTitle: name, in: nexus)
            let meta = NexusPaths.topicMetadataURL(forTitle: name, in: nexus)
            try Filesystem.createFolderWithMetadata(folderURL: folder, metadataURL: meta, metadata: topic)

            if let updater = indexUpdater {
                do { try updater.upsertContext(topic) } catch { self.pendingError = error }
            }

            topics.append(topic)
            topics = OrderResolver.resolve(
                topics,
                persistedOrder: readPersistedTopicOrder(),
                titleKeyPath: \Topic.title
            )
            return topic
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func rename(_ topic: Topic, to newName: String) async throws {
        do {
            try TopicValidator.validate(
                title: newName,
                existing: topics,
                excluding: topic
            )

            let oldFolder = NexusPaths.topicFolderURL(forTitle: topic.title, in: nexus)
            let newFolder = NexusPaths.topicFolderURL(forTitle: newName, in: nexus)
            try Filesystem.renameFolder(from: oldFolder, to: newFolder)

            var updated = topic
            updated.title = newName
            updated.modifiedAt = Date()
            let newMeta = NexusPaths.topicMetadataURL(forTitle: newName, in: nexus)
            do {
                try updated.save(to: newMeta)
            } catch let saveError {
                // Roll back the folder rename. If revert fails, on-disk state
                // is inconsistent — surface with RenameAtomicityError.
                do {
                    try Filesystem.renameFolder(from: newFolder, to: oldFolder)
                    throw saveError
                } catch let revertError {
                    let combined = RenameAtomicityError(saveError: saveError, revertError: revertError)
                    self.pendingError = combined
                    throw combined
                }
            }

            if let updater = indexUpdater {
                do { try updater.upsertContext(updated) } catch { self.pendingError = error }
            }

            if let i = topics.firstIndex(where: { $0.id == topic.id }) {
                topics[i] = updated
                topics = OrderResolver.resolve(
                    topics,
                    persistedOrder: readPersistedTopicOrder(),
                    titleKeyPath: \Topic.title
                )
            }
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func updateIcon(_ topic: Topic, to icon: String?) async throws {
        do {
            var updated = topic
            updated.icon = icon
            updated.modifiedAt = Date()
            let meta = NexusPaths.topicMetadataURL(forTitle: topic.title, in: nexus)
            try updated.save(to: meta)
            // `icon` is an indexed `contexts` column — re-upsert.
            if let updater = indexUpdater {
                do { try updater.upsertContext(updated) } catch { self.pendingError = error }
            }
            if let i = topics.firstIndex(where: { $0.id == topic.id }) {
                topics[i] = updated
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func delete(_ topic: Topic) async throws {
        do {
            let folder = NexusPaths.topicFolderURL(forTitle: topic.title, in: nexus)
            try Filesystem.moveToTrash(folder, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deleteContext(id: topic.id) } catch { self.pendingError = error }
            }
            topics.removeAll { $0.id == topic.id }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Reorders Topics in response to a sidebar drag (v0.2.8.0). Matches the
    /// SwiftUI `.onMove(perform:)` signature. New full ID order persists to
    /// `.nexus/state.json`.
    func reorderTopics(fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = topics
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != topics else { return }
        topics = arr
        do {
            try OrderPersister.setTopicOrder(arr.map(\.id), in: nexus)
        } catch {
            self.pendingError = error
        }
    }

    /// Reads the persisted Topic sibling order from `.nexus/state.json`. Returns
    /// nil if no state.json exists or no `topicOrder` has been recorded — the
    /// resolver falls back to alphabetic in that case.
    private func readPersistedTopicOrder() -> [String]? {
        let url = NexusPaths.nexusStateURL(in: nexus)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (try? AtomicJSON.decode(NexusState.self, from: url))?.topicOrder
    }
}
