import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderTopics/Projects

@MainActor
@Observable
final class TopicManager {
    private(set) var topics: [Topic] = []
    /// Keyed by parent Topic ID.
    private(set) var projectsByParent: [String: [Project]] = [:]
    var pendingError: (any Error)?

    private let nexus: Nexus
    private let contextProvider: @MainActor () -> NexusContext

    /// Current Nexus ID — used by the drag system's cross-window guard.
    var nexusID: String { nexus.id }

    init(nexus: Nexus, contextProvider: @escaping @MainActor () -> NexusContext) {
        self.nexus = nexus
        self.contextProvider = contextProvider
    }

    // MARK: - Accessors

    func projects(in topic: Topic) -> [Project] {
        projectsByParent[topic.id] ?? []
    }

    // MARK: - Load

    func loadAll() async {
        do {
            let topicsDir = NexusPaths.topicsDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(topicsDir)

            var loadedTopics: [Topic] = []
            var loadedProjects: [String: [Project]] = [:]

            let topicFolders = try Filesystem.childFolders(of: topicsDir)
            for folder in topicFolders {
                let metaURL = folder.appendingPathComponent("_topic.json")
                guard Filesystem.fileExists(at: metaURL) else { continue }  // skip cosmetic folder
                guard let topic = try? Topic.load(from: metaURL) else { continue }
                loadedTopics.append(topic)

                let projectFiles = try Filesystem.children(of: folder) { url in
                    url.pathExtension == "json" && url.deletingPathExtension().pathExtension == "project"
                }
                let projects = projectFiles.compactMap { try? Project.load(from: $0) }
                    .map { p -> Project in
                        var copy = p
                        copy.parents = [topic.id]  // file-location-derived parent
                        return copy
                    }
                loadedProjects[topic.id] = OrderResolver.resolve(
                    projects,
                    persistedOrder: topic.projectOrder,
                    titleKeyPath: \Project.title
                )
            }

            self.topics = OrderResolver.resolve(
                loadedTopics,
                persistedOrder: readPersistedTopicOrder(),
                titleKeyPath: \Topic.title
            )
            self.projectsByParent = loadedProjects
            self.pendingError = nil
        } catch {
            self.topics = []
            self.projectsByParent = [:]
            self.pendingError = error
        }
    }

    // MARK: - Topic CRUD

    func createTopic(name: String, parents: [String], icon: String?) async throws {
        do {
            try TopicValidator.validate(
                title: name, parents: parents,
                existing: topics, context: contextProvider()
            )

            let topic = Topic(
                id: ULID.generate(),
                title: name,
                parents: parents,
                icon: icon,
                blocks: [],
                modifiedAt: Date()
            )
            let folder = NexusPaths.topicFolderURL(forTitle: name, in: nexus)
            let meta = NexusPaths.topicMetadataURL(forTitle: name, in: nexus)
            try Filesystem.createFolderWithMetadata(folderURL: folder, metadataURL: meta, metadata: topic)

            topics.append(topic)
            projectsByParent[topic.id] = []
            topics = OrderResolver.resolve(
                topics,
                persistedOrder: readPersistedTopicOrder(),
                titleKeyPath: \Topic.title
            )
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renameTopic(_ topic: Topic, to newName: String) async throws {
        do {
            try TopicValidator.validate(
                title: newName, parents: topic.parents,
                existing: topics, context: contextProvider(),
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

    func updateTopicParents(_ topic: Topic, to parents: [String]) async throws {
        do {
            try TopicValidator.validate(
                title: topic.title, parents: parents,
                existing: topics, context: contextProvider(),
                excluding: topic
            )

            var updated = topic
            updated.parents = parents
            updated.modifiedAt = Date()
            let meta = NexusPaths.topicMetadataURL(forTitle: topic.title, in: nexus)
            try updated.save(to: meta)

            if let i = topics.firstIndex(where: { $0.id == topic.id }) {
                topics[i] = updated
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func updateTopicIcon(_ topic: Topic, to icon: String?) async throws {
        do {
            var updated = topic
            updated.icon = icon
            updated.modifiedAt = Date()
            let meta = NexusPaths.topicMetadataURL(forTitle: topic.title, in: nexus)
            try updated.save(to: meta)
            if let i = topics.firstIndex(where: { $0.id == topic.id }) {
                topics[i] = updated
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Deletes a Topic. If `promotingProjects` is true (default), Projects inside
    /// are converted to standalone Topics inheriting the deleted Topic's parents.
    /// On filename collision with an existing top-level Topic, auto-suffixes (2), (3), …
    func deleteTopic(_ topic: Topic, promotingProjects: Bool = true) async throws {
        do {
            let projects = projectsByParent[topic.id] ?? []

            if promotingProjects {
                for project in projects {
                    try await promoteProjectToTopic(project, inheritedParents: topic.parents)
                }
            }

            let folder = NexusPaths.topicFolderURL(forTitle: topic.title, in: nexus)
            try Filesystem.moveToTrash(folder, in: nexus)
            topics.removeAll { $0.id == topic.id }
            projectsByParent.removeValue(forKey: topic.id)
        } catch {
            self.pendingError = error
            throw error
        }
    }

    private func promoteProjectToTopic(_ project: Project, inheritedParents: [String]) async throws {
        var promotedName = project.title
        var suffix = 2
        while topics.contains(where: { $0.title.lowercased() == promotedName.lowercased() }) {
            promotedName = "\(project.title) (\(suffix))"
            suffix += 1
        }
        let topic = Topic(
            id: ULID.generate(),  // new identity at tier-2; old Project id is dropped
            title: promotedName,
            parents: inheritedParents,
            icon: project.icon,
            blocks: project.blocks,
            modifiedAt: Date()
        )
        let folder = NexusPaths.topicFolderURL(forTitle: promotedName, in: nexus)
        let meta = NexusPaths.topicMetadataURL(forTitle: promotedName, in: nexus)
        try Filesystem.createFolderWithMetadata(folderURL: folder, metadataURL: meta, metadata: topic)
        topics.append(topic)
        projectsByParent[topic.id] = []
    }

    // MARK: - Project CRUD

    func createProject(name: String, inTopic parent: Topic, icon: String?) async throws {
        do {
            let existing = projectsByParent[parent.id] ?? []
            let context = NexusContext(
                lookupSpace: { _ in nil },
                lookupTopic: { [topics] id in topics.first { $0.id == id } },
                lookupProject: { _ in nil },
                lookupVault: { _ in nil }
            )
            try ProjectValidator.validate(
                title: name,
                parents: [parent.id],
                fileLocation: .init(parentFolderTitle: parent.title),
                existing: existing,
                context: context
            )

            let project = Project(
                id: ULID.generate(),
                title: name,
                parents: [parent.id],
                linkedRelations: [],
                icon: icon,
                blocks: [],
                modifiedAt: Date()
            )
            let url = NexusPaths.projectFileURL(
                forTitle: name, inTopicTitled: parent.title, in: nexus
            )
            try project.save(to: url)

            var arr = projectsByParent[parent.id] ?? []
            arr.append(project)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: parent.projectOrder,
                titleKeyPath: \Project.title
            )
            projectsByParent[parent.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renameProject(_ project: Project, to newName: String) async throws {
        do {
            guard let parentID = project.parents.first,
                let parent = topics.first(where: { $0.id == parentID })
            else { throw ProjectValidator.ValidationError.missingParent }

            let existing = projectsByParent[parent.id] ?? []
            let context = NexusContext(
                lookupSpace: { _ in nil },
                lookupTopic: { [topics] id in topics.first { $0.id == id } },
                lookupProject: { _ in nil },
                lookupVault: { _ in nil }
            )
            try ProjectValidator.validate(
                title: newName,
                parents: [parent.id],
                fileLocation: .init(parentFolderTitle: parent.title),
                existing: existing,
                context: context,
                excluding: project
            )

            let oldURL = NexusPaths.projectFileURL(
                forTitle: project.title, inTopicTitled: parent.title, in: nexus
            )
            let newURL = NexusPaths.projectFileURL(
                forTitle: newName, inTopicTitled: parent.title, in: nexus
            )
            var updated = project
            updated.title = newName
            updated.modifiedAt = Date()
            try Filesystem.renameFile(from: oldURL, to: newURL)
            do {
                try updated.save(to: newURL)
            } catch let saveError {
                do {
                    try Filesystem.renameFile(from: newURL, to: oldURL)
                    throw saveError
                } catch let revertError {
                    let combined = RenameAtomicityError(saveError: saveError, revertError: revertError)
                    self.pendingError = combined
                    throw combined
                }
            }

            var arr = projectsByParent[parent.id] ?? []
            if let i = arr.firstIndex(where: { $0.id == project.id }) {
                arr[i] = updated
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: parent.projectOrder,
                    titleKeyPath: \Project.title
                )
            }
            projectsByParent[parent.id] = arr
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func moveProject(_ project: Project, toTopic newParent: Topic) async throws {
        do {
            guard let oldParentID = project.parents.first,
                let oldParent = topics.first(where: { $0.id == oldParentID })
            else { throw ProjectValidator.ValidationError.missingParent }
            guard oldParent.id != newParent.id else { return }

            let oldURL = NexusPaths.projectFileURL(
                forTitle: project.title, inTopicTitled: oldParent.title, in: nexus
            )
            let newURL = NexusPaths.projectFileURL(
                forTitle: project.title, inTopicTitled: newParent.title, in: nexus
            )

            var updated = project
            updated.parents = [newParent.id]
            updated.modifiedAt = Date()
            try Filesystem.renameFile(from: oldURL, to: newURL)
            do {
                try updated.save(to: newURL)
            } catch let saveError {
                do {
                    try Filesystem.renameFile(from: newURL, to: oldURL)
                    throw saveError
                } catch let revertError {
                    let combined = RenameAtomicityError(saveError: saveError, revertError: revertError)
                    self.pendingError = combined
                    throw combined
                }
            }

            var oldArr = projectsByParent[oldParent.id] ?? []
            oldArr.removeAll { $0.id == project.id }
            projectsByParent[oldParent.id] = oldArr

            var newArr = projectsByParent[newParent.id] ?? []
            newArr.append(updated)
            newArr = OrderResolver.resolve(
                newArr,
                persistedOrder: newParent.projectOrder,
                titleKeyPath: \Project.title
            )
            projectsByParent[newParent.id] = newArr
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func deleteProject(_ project: Project) async throws {
        do {
            guard let parentID = project.parents.first,
                let parent = topics.first(where: { $0.id == parentID })
            else { throw ProjectValidator.ValidationError.missingParent }

            let url = NexusPaths.projectFileURL(
                forTitle: project.title, inTopicTitled: parent.title, in: nexus
            )
            try Filesystem.moveToTrash(url, in: nexus)
            var arr = projectsByParent[parent.id] ?? []
            arr.removeAll { $0.id == project.id }
            projectsByParent[parent.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func updateProjectIcon(_ project: Project, to icon: String?) async throws {
        do {
            guard let parentID = project.parents.first,
                let parent = topics.first(where: { $0.id == parentID })
            else { throw ProjectValidator.ValidationError.missingParent }

            var updated = project
            updated.icon = icon
            updated.modifiedAt = Date()
            let url = NexusPaths.projectFileURL(
                forTitle: project.title, inTopicTitled: parent.title, in: nexus
            )
            try updated.save(to: url)
            var arr = projectsByParent[parent.id] ?? []
            if let i = arr.firstIndex(where: { $0.id == project.id }) {
                arr[i] = updated
            }
            projectsByParent[parent.id] = arr
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

    /// Reorders Projects within `topic`. New ID order persists to the parent
    /// Topic's `_topic.json` sidecar.
    func reorderProjects(in topic: Topic, fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = projectsByParent[topic.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        projectsByParent[topic.id] = arr
        do {
            try OrderPersister.setProjectOrder(arr.map(\.id), in: topic, nexus: nexus)
            // Keep the in-memory Topic's projectOrder in sync so subsequent
            // resolve() calls (after rename, create, etc.) see the latest order.
            if let i = topics.firstIndex(where: { $0.id == topic.id }) {
                topics[i].projectOrder = arr.map(\.id)
            }
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
