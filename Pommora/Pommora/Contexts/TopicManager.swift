import Foundation
import Observation

@MainActor
@Observable
final class TopicManager {
    private(set) var topics: [Topic] = []
    /// Keyed by parent Topic ID.
    private(set) var subtopicsByParent: [String: [Subtopic]] = [:]
    var pendingError: (any Error)?

    private let nexus: Nexus
    private let contextProvider: @MainActor () -> NexusContext

    init(nexus: Nexus, contextProvider: @escaping @MainActor () -> NexusContext) {
        self.nexus = nexus
        self.contextProvider = contextProvider
    }

    // MARK: - Accessors

    func subtopics(in topic: Topic) -> [Subtopic] {
        subtopicsByParent[topic.id] ?? []
    }

    // MARK: - Load

    func loadAll() async {
        do {
            let topicsDir = NexusPaths.topicsDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(topicsDir)

            var loadedTopics: [Topic] = []
            var loadedSubs: [String: [Subtopic]] = [:]

            let topicFolders = try Filesystem.childFolders(of: topicsDir)
            for folder in topicFolders {
                let metaURL = folder.appendingPathComponent("_topic.json")
                guard Filesystem.fileExists(at: metaURL) else { continue }  // skip cosmetic folder
                guard let topic = try? Topic.load(from: metaURL) else { continue }
                loadedTopics.append(topic)

                let subFiles = try Filesystem.children(of: folder) { url in
                    url.pathExtension == "json" && url.deletingPathExtension().pathExtension == "subtopic"
                }
                let subs = subFiles.compactMap { try? Subtopic.load(from: $0) }
                    .map { st -> Subtopic in
                        var copy = st
                        copy.parents = [topic.id]  // file-location-derived parent
                        return copy
                    }
                loadedSubs[topic.id] = subs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            }

            self.topics = loadedTopics.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            self.subtopicsByParent = loadedSubs
            self.pendingError = nil
        } catch {
            self.topics = []
            self.subtopicsByParent = [:]
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
            subtopicsByParent[topic.id] = []
            topics.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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
                topics.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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

    /// Deletes a Topic. If `promotingSubtopics` is true (default), Sub-topics inside
    /// are converted to standalone Topics inheriting the deleted Topic's parents.
    /// On filename collision with an existing top-level Topic, auto-suffixes (2), (3), …
    func deleteTopic(_ topic: Topic, promotingSubtopics: Bool = true) async throws {
        do {
            let subs = subtopicsByParent[topic.id] ?? []

            if promotingSubtopics {
                for sub in subs {
                    try await promoteSubtopicToTopic(sub, inheritedParents: topic.parents)
                }
            }

            let folder = NexusPaths.topicFolderURL(forTitle: topic.title, in: nexus)
            try Filesystem.moveToTrash(folder, in: nexus)
            topics.removeAll { $0.id == topic.id }
            subtopicsByParent.removeValue(forKey: topic.id)
        } catch {
            self.pendingError = error
            throw error
        }
    }

    private func promoteSubtopicToTopic(_ sub: Subtopic, inheritedParents: [String]) async throws {
        var promotedName = sub.title
        var suffix = 2
        while topics.contains(where: { $0.title.lowercased() == promotedName.lowercased() }) {
            promotedName = "\(sub.title) (\(suffix))"
            suffix += 1
        }
        let topic = Topic(
            id: ULID.generate(),  // new identity at tier-2; old Subtopic id is dropped
            title: promotedName,
            parents: inheritedParents,
            icon: sub.icon,
            blocks: sub.blocks,
            modifiedAt: Date()
        )
        let folder = NexusPaths.topicFolderURL(forTitle: promotedName, in: nexus)
        let meta = NexusPaths.topicMetadataURL(forTitle: promotedName, in: nexus)
        try Filesystem.createFolderWithMetadata(folderURL: folder, metadataURL: meta, metadata: topic)
        topics.append(topic)
        subtopicsByParent[topic.id] = []
    }

    // MARK: - Subtopic CRUD

    func createSubtopic(name: String, inTopic parent: Topic, icon: String?) async throws {
        do {
            let existing = subtopicsByParent[parent.id] ?? []
            let context = NexusContext(
                lookupSpace: { _ in nil },
                lookupTopic: { [topics] id in topics.first { $0.id == id } },
                lookupSubtopic: { _ in nil },
                lookupVault: { _ in nil }
            )
            try SubtopicValidator.validate(
                title: name,
                parents: [parent.id],
                fileLocation: .init(parentFolderTitle: parent.title),
                existing: existing,
                context: context
            )

            let sub = Subtopic(
                id: ULID.generate(),
                title: name,
                parents: [parent.id],
                linkedRelations: [],
                icon: icon,
                blocks: [],
                modifiedAt: Date()
            )
            let url = NexusPaths.subtopicFileURL(
                forTitle: name, inTopicTitled: parent.title, in: nexus
            )
            try sub.save(to: url)

            var arr = subtopicsByParent[parent.id] ?? []
            arr.append(sub)
            arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            subtopicsByParent[parent.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renameSubtopic(_ sub: Subtopic, to newName: String) async throws {
        do {
            guard let parentID = sub.parents.first,
                let parent = topics.first(where: { $0.id == parentID })
            else { throw SubtopicValidator.ValidationError.missingParent }

            let existing = subtopicsByParent[parent.id] ?? []
            let context = NexusContext(
                lookupSpace: { _ in nil },
                lookupTopic: { [topics] id in topics.first { $0.id == id } },
                lookupSubtopic: { _ in nil },
                lookupVault: { _ in nil }
            )
            try SubtopicValidator.validate(
                title: newName,
                parents: [parent.id],
                fileLocation: .init(parentFolderTitle: parent.title),
                existing: existing,
                context: context,
                excluding: sub
            )

            let oldURL = NexusPaths.subtopicFileURL(
                forTitle: sub.title, inTopicTitled: parent.title, in: nexus
            )
            let newURL = NexusPaths.subtopicFileURL(
                forTitle: newName, inTopicTitled: parent.title, in: nexus
            )
            var updated = sub
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

            var arr = subtopicsByParent[parent.id] ?? []
            if let i = arr.firstIndex(where: { $0.id == sub.id }) {
                arr[i] = updated
                arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            }
            subtopicsByParent[parent.id] = arr
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func moveSubtopic(_ sub: Subtopic, toTopic newParent: Topic) async throws {
        do {
            guard let oldParentID = sub.parents.first,
                let oldParent = topics.first(where: { $0.id == oldParentID })
            else { throw SubtopicValidator.ValidationError.missingParent }
            guard oldParent.id != newParent.id else { return }

            let oldURL = NexusPaths.subtopicFileURL(
                forTitle: sub.title, inTopicTitled: oldParent.title, in: nexus
            )
            let newURL = NexusPaths.subtopicFileURL(
                forTitle: sub.title, inTopicTitled: newParent.title, in: nexus
            )

            var updated = sub
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

            var oldArr = subtopicsByParent[oldParent.id] ?? []
            oldArr.removeAll { $0.id == sub.id }
            subtopicsByParent[oldParent.id] = oldArr

            var newArr = subtopicsByParent[newParent.id] ?? []
            newArr.append(updated)
            newArr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            subtopicsByParent[newParent.id] = newArr
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func deleteSubtopic(_ sub: Subtopic) async throws {
        do {
            guard let parentID = sub.parents.first,
                let parent = topics.first(where: { $0.id == parentID })
            else { throw SubtopicValidator.ValidationError.missingParent }

            let url = NexusPaths.subtopicFileURL(
                forTitle: sub.title, inTopicTitled: parent.title, in: nexus
            )
            try Filesystem.moveToTrash(url, in: nexus)
            var arr = subtopicsByParent[parent.id] ?? []
            arr.removeAll { $0.id == sub.id }
            subtopicsByParent[parent.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func updateSubtopicIcon(_ sub: Subtopic, to icon: String?) async throws {
        do {
            guard let parentID = sub.parents.first,
                let parent = topics.first(where: { $0.id == parentID })
            else { throw SubtopicValidator.ValidationError.missingParent }

            var updated = sub
            updated.icon = icon
            updated.modifiedAt = Date()
            let url = NexusPaths.subtopicFileURL(
                forTitle: sub.title, inTopicTitled: parent.title, in: nexus
            )
            try updated.save(to: url)
            var arr = subtopicsByParent[parent.id] ?? []
            if let i = arr.firstIndex(where: { $0.id == sub.id }) {
                arr[i] = updated
            }
            subtopicsByParent[parent.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }
}
