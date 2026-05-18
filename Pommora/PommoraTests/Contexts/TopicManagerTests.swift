import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("TopicManager")
struct TopicManagerTests {

    @Test("createTopic writes folder + _topic.json; loadAll reads them back")
    func createTopic() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createTopic(name: "Productivity", parents: [], icon: nil)
        let folder = NexusPaths.topicFolderURL(forTitle: "Productivity", in: nexus)
        let meta = NexusPaths.topicMetadataURL(forTitle: "Productivity", in: nexus)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: meta.path))
        #expect(manager.topics.count == 1)
        #expect(manager.topics.first?.title == "Productivity")
    }

    @Test("createSubtopic writes .subtopic.json inside parent Topic folder")
    func createSubtopic() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createTopic(name: "Productivity", parents: [], icon: nil)
        let topic = manager.topics.first!
        try await manager.createSubtopic(name: "GTD method", inTopic: topic, icon: nil)

        let stURL = NexusPaths.subtopicFileURL(
            forTitle: "GTD method", inTopicTitled: "Productivity", in: nexus
        )
        #expect(FileManager.default.fileExists(atPath: stURL.path))
        #expect(manager.subtopics(in: topic).count == 1)
        #expect(manager.subtopics(in: topic).first?.title == "GTD method")
    }

    @Test("renameTopic moves the folder; sub-topics inside follow")
    func renameTopic() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createTopic(name: "Productivity", parents: [], icon: nil)
        let topic = manager.topics.first!
        try await manager.createSubtopic(name: "GTD", inTopic: topic, icon: nil)

        try await manager.renameTopic(topic, to: "Workflows")
        let newMeta = NexusPaths.topicMetadataURL(forTitle: "Workflows", in: nexus)
        let newSub = NexusPaths.subtopicFileURL(
            forTitle: "GTD", inTopicTitled: "Workflows", in: nexus
        )
        #expect(FileManager.default.fileExists(atPath: newMeta.path))
        #expect(FileManager.default.fileExists(atPath: newSub.path))
        let oldFolder = NexusPaths.topicFolderURL(forTitle: "Productivity", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: oldFolder.path))
    }

    @Test("deleteTopic(promotingSubtopics: true) moves sub-topics out as standalone Topics")
    func deletePromote() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createTopic(name: "Productivity", parents: [], icon: nil)
        let topic = manager.topics.first!
        try await manager.createSubtopic(name: "GTD", inTopic: topic, icon: nil)
        try await manager.createSubtopic(name: "Time blocking", inTopic: topic, icon: nil)

        try await manager.deleteTopic(topic, promotingSubtopics: true)
        // Parent folder gone
        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.topicFolderURL(forTitle: "Productivity", in: nexus).path
            ))
        // Sub-topics promoted to top-level Topics with their own folders
        let gtdMeta = NexusPaths.topicMetadataURL(forTitle: "GTD", in: nexus)
        let tbMeta = NexusPaths.topicMetadataURL(forTitle: "Time blocking", in: nexus)
        #expect(FileManager.default.fileExists(atPath: gtdMeta.path))
        #expect(FileManager.default.fileExists(atPath: tbMeta.path))
        // Manager state: 2 top-level topics, no subtopics
        #expect(manager.topics.count == 2)
        for t in manager.topics {
            #expect(manager.subtopics(in: t).isEmpty)
        }
    }

    @Test("deleteTopic(promotingSubtopics: false) cascades")
    func deleteCascade() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createTopic(name: "Productivity", parents: [], icon: nil)
        let topic = manager.topics.first!
        try await manager.createSubtopic(name: "GTD", inTopic: topic, icon: nil)

        try await manager.deleteTopic(topic, promotingSubtopics: false)
        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.topicFolderURL(forTitle: "Productivity", in: nexus).path
            ))
        #expect(manager.topics.isEmpty)
    }

    @Test("moveSubtopic relocates the file to new parent's folder")
    func moveSubtopic() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createTopic(name: "A", parents: [], icon: nil)
        try await manager.createTopic(name: "B", parents: [], icon: nil)
        let a = manager.topics.first { $0.title == "A" }!
        let b = manager.topics.first { $0.title == "B" }!
        try await manager.createSubtopic(name: "X", inTopic: a, icon: nil)
        let sub = manager.subtopics(in: a).first!

        try await manager.moveSubtopic(sub, toTopic: b)
        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.subtopicFileURL(forTitle: "X", inTopicTitled: "A", in: nexus).path
            ))
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.subtopicFileURL(forTitle: "X", inTopicTitled: "B", in: nexus).path
            ))
        #expect(manager.subtopics(in: a).isEmpty)
        #expect(manager.subtopics(in: b).count == 1)
    }

    // MARK: - helper

    private func setup() async throws -> (Nexus, TopicManager) {
        let nexus = try TempNexus.make()
        let manager = TopicManager(nexus: nexus, contextProvider: { NexusContext.empty })
        await manager.loadAll()
        return (nexus, manager)
    }
}
