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

    @Test("createProject writes .project.json inside parent Topic folder")
    func createProject() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createTopic(name: "Productivity", parents: [], icon: nil)
        let topic = manager.topics.first!
        try await manager.createProject(name: "GTD method", inTopic: topic, icon: nil)

        let projectURL = NexusPaths.projectFileURL(
            forTitle: "GTD method", inTopicTitled: "Productivity", in: nexus
        )
        #expect(FileManager.default.fileExists(atPath: projectURL.path))
        #expect(manager.projects(in: topic).count == 1)
        #expect(manager.projects(in: topic).first?.title == "GTD method")
    }

    @Test("renameTopic moves the folder; Projects inside follow")
    func renameTopic() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createTopic(name: "Productivity", parents: [], icon: nil)
        let topic = manager.topics.first!
        try await manager.createProject(name: "GTD", inTopic: topic, icon: nil)

        try await manager.renameTopic(topic, to: "Workflows")
        let newMeta = NexusPaths.topicMetadataURL(forTitle: "Workflows", in: nexus)
        let newProject = NexusPaths.projectFileURL(
            forTitle: "GTD", inTopicTitled: "Workflows", in: nexus
        )
        #expect(FileManager.default.fileExists(atPath: newMeta.path))
        #expect(FileManager.default.fileExists(atPath: newProject.path))
        let oldFolder = NexusPaths.topicFolderURL(forTitle: "Productivity", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: oldFolder.path))
    }

    @Test("deleteTopic(promotingProjects: true) moves Projects out as standalone Topics")
    func deletePromote() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createTopic(name: "Productivity", parents: [], icon: nil)
        let topic = manager.topics.first!
        try await manager.createProject(name: "GTD", inTopic: topic, icon: nil)
        try await manager.createProject(name: "Time blocking", inTopic: topic, icon: nil)

        try await manager.deleteTopic(topic, promotingProjects: true)
        // Parent folder gone
        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.topicFolderURL(forTitle: "Productivity", in: nexus).path
            ))
        // Projects promoted to top-level Topics with their own folders
        let gtdMeta = NexusPaths.topicMetadataURL(forTitle: "GTD", in: nexus)
        let tbMeta = NexusPaths.topicMetadataURL(forTitle: "Time blocking", in: nexus)
        #expect(FileManager.default.fileExists(atPath: gtdMeta.path))
        #expect(FileManager.default.fileExists(atPath: tbMeta.path))
        // Manager state: 2 top-level topics, no Projects
        #expect(manager.topics.count == 2)
        for t in manager.topics {
            #expect(manager.projects(in: t).isEmpty)
        }
    }

    @Test("deleteTopic(promotingProjects: false) cascades")
    func deleteCascade() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createTopic(name: "Productivity", parents: [], icon: nil)
        let topic = manager.topics.first!
        try await manager.createProject(name: "GTD", inTopic: topic, icon: nil)

        try await manager.deleteTopic(topic, promotingProjects: false)
        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.topicFolderURL(forTitle: "Productivity", in: nexus).path
            ))
        #expect(manager.topics.isEmpty)
    }

    @Test("moveProject relocates the file to new parent's folder")
    func moveProject() async throws {
        let (nexus, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createTopic(name: "A", parents: [], icon: nil)
        try await manager.createTopic(name: "B", parents: [], icon: nil)
        let a = manager.topics.first { $0.title == "A" }!
        let b = manager.topics.first { $0.title == "B" }!
        try await manager.createProject(name: "X", inTopic: a, icon: nil)
        let project = manager.projects(in: a).first!

        try await manager.moveProject(project, toTopic: b)
        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.projectFileURL(forTitle: "X", inTopicTitled: "A", in: nexus).path
            ))
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.projectFileURL(forTitle: "X", inTopicTitled: "B", in: nexus).path
            ))
        #expect(manager.projects(in: a).isEmpty)
        #expect(manager.projects(in: b).count == 1)
    }

    // MARK: - helper

    private func setup() async throws -> (Nexus, TopicManager) {
        let nexus = try TempNexus.make()
        let manager = TopicManager(nexus: nexus, contextProvider: { NexusContext.empty })
        await manager.loadAll()
        return (nexus, manager)
    }
}
