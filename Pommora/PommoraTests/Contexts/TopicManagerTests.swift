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

        try await manager.create(name: "Productivity", icon: nil)
        let folder = NexusPaths.topicFolderURL(forTitle: "Productivity", in: nexus)
        let meta = NexusPaths.topicMetadataURL(forTitle: "Productivity", in: nexus)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: meta.path))
        #expect(manager.topics.count == 1)
        #expect(manager.topics.first?.title == "Productivity")
    }

    @Test("renameTopic moves the folder")
    func renameTopic() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.create(name: "Productivity", icon: nil)
        let topic = manager.topics.first!

        try await manager.rename(topic, to: "Workflows")
        let newMeta = NexusPaths.topicMetadataURL(forTitle: "Workflows", in: nexus)
        #expect(FileManager.default.fileExists(atPath: newMeta.path))
        let oldFolder = NexusPaths.topicFolderURL(forTitle: "Productivity", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: oldFolder.path))
    }

    @Test("deleteTopic trashes the folder and drops from topics array")
    func deleteTopic() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.create(name: "Productivity", icon: nil)
        let topic = manager.topics.first!

        try await manager.delete(topic)
        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.topicFolderURL(forTitle: "Productivity", in: nexus).path
            ))
        #expect(manager.topics.isEmpty)
    }

    // MARK: - helper

    private func setup() async throws -> (Nexus, TopicManager) {
        let nexus = try TempNexus.make()
        let manager = TopicManager(nexus: nexus)
        await manager.loadAll()
        return (nexus, manager)
    }
}
