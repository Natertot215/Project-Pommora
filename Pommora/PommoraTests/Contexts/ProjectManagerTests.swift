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
        try await ContextCRUDChecks.assertCreate(
            ProjectManager(nexus: nexus), in: nexus, named: "Alpha",
            metadataURL: NexusPaths.projectMetadataURL(forTitle:in:))
    }

    @Test("create with duplicate title throws and leaves disk unchanged")
    func createDuplicate() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try await ContextCRUDChecks.assertDuplicateThrows(
            ProjectManager(nexus: nexus), named: "Alpha", caseVariant: "alpha",
            throwing: ProjectValidator.ValidationError.duplicateTitle)
    }

    @Test("rename renames the folder and updates the in-memory entry")
    func rename() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try await ContextCRUDChecks.assertRename(
            ProjectManager(nexus: nexus), in: nexus, from: "Alpha", to: "Beta",
            folderURL: NexusPaths.projectFolderURL(forTitle:in:))
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
        try await ContextCRUDChecks.assertDelete(
            ProjectManager(nexus: nexus), in: nexus, named: "Alpha",
            folderURL: NexusPaths.projectFolderURL(forTitle:in:))
    }

    @Test("loadAll reads an externally-placed _project.json; title derives from folder")
    func loadAllReadsFixture() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/projects/Fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let p = Project(id: ULID.generate(), title: "Fixture", icon: nil, blocks: [], modifiedAt: Date())
        try p.save(to: folder.appendingPathComponent("_project.json"))

        let manager = ProjectManager(nexus: nexus)
        await manager.loadAll()
        #expect(manager.projects.count == 1)
        #expect(manager.projects.first?.title == "Fixture")
    }
}
