import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("TopicManager")
struct TopicManagerTests {

    @Test("createTopic writes folder + _topic.json; loadAll reads them back")
    func createTopic() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try await ContextCRUDChecks.assertCreate(
            TopicManager(nexus: nexus), in: nexus, named: "Productivity",
            metadataURL: NexusPaths.topicMetadataURL(forTitle:in:))
    }

    @Test("renameTopic moves the folder")
    func renameTopic() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try await ContextCRUDChecks.assertRename(
            TopicManager(nexus: nexus), in: nexus, from: "Productivity", to: "Workflows",
            folderURL: NexusPaths.topicFolderURL(forTitle:in:))
    }

    @Test("deleteTopic trashes the folder and drops from topics array")
    func deleteTopic() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try await ContextCRUDChecks.assertDelete(
            TopicManager(nexus: nexus), in: nexus, named: "Productivity",
            folderURL: NexusPaths.topicFolderURL(forTitle:in:))
    }
}
