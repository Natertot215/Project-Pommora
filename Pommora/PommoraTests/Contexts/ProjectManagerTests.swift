import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("ProjectManager")
struct ProjectManagerTests {

    @Test("create writes _project.json on disk and appends to projects")
    func create() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ProjectManager(nexus: nexus)
        await manager.loadAll()

        try await manager.create(name: "Alpha", icon: "star")
        let metaURL = NexusPaths.projectMetadataURL(forTitle: "Alpha", in: nexus)
        #expect(FileManager.default.fileExists(atPath: metaURL.path))
        #expect(manager.projects.count == 1)
        #expect(manager.projects.first?.title == "Alpha")
    }

    @Test("create with duplicate title throws and leaves disk unchanged")
    func createDuplicate() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ProjectManager(nexus: nexus)
        await manager.loadAll()
        try await manager.create(name: "Alpha", icon: nil)

        await #expect(throws: ProjectValidator.ValidationError.duplicateTitle) {
            try await manager.create(name: "alpha", icon: nil)
        }
        #expect(manager.projects.count == 1)
    }

    @Test("rename renames the folder and updates the in-memory entry")
    func rename() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ProjectManager(nexus: nexus)
        await manager.loadAll()
        try await manager.create(name: "Alpha", icon: nil)
        let project = manager.projects.first!

        try await manager.rename(project, to: "Beta")
        let oldFolder = NexusPaths.projectFolderURL(forTitle: "Alpha", in: nexus)
        let newFolder = NexusPaths.projectFolderURL(forTitle: "Beta", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: oldFolder.path))
        #expect(FileManager.default.fileExists(atPath: newFolder.path))
        #expect(manager.projects.first?.title == "Beta")
    }

    @Test("updateIcon mutates icon and bumps modified_at on disk")
    func updateIcon() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ProjectManager(nexus: nexus)
        await manager.loadAll()
        try await manager.create(name: "Alpha", icon: nil)
        let project = manager.projects.first!

        try await manager.updateIcon(project, to: "folder.fill")
        #expect(manager.projects.first?.icon == "folder.fill")
        let metaURL = NexusPaths.projectMetadataURL(forTitle: "Alpha", in: nexus)
        let reloaded = try AtomicJSON.decode(Project.self, from: metaURL)
        #expect(reloaded.icon == "folder.fill")
    }

    @Test("delete trashes the folder and drops from projects array")
    func delete() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ProjectManager(nexus: nexus)
        await manager.loadAll()
        try await manager.create(name: "Alpha", icon: nil)
        let project = manager.projects.first!

        try await manager.delete(project)
        let folder = NexusPaths.projectFolderURL(forTitle: "Alpha", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(manager.projects.isEmpty)
    }
}
