import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("AreaManager")
struct AreaManagerTests {

    @Test("create writes a _area.json folder on disk and adds to areas")
    func create() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try await ContextCRUDChecks.assertCreate(
            AreaManager(nexus: nexus), in: nexus, named: "Personal",
            metadataURL: NexusPaths.areaMetadataURL(forTitle:in:))
    }

    @Test("create with duplicate title throws + leaves disk unchanged")
    func createDuplicate() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try await ContextCRUDChecks.assertDuplicateThrows(
            AreaManager(nexus: nexus), named: "Personal", caseVariant: "personal",
            throwing: AreaValidator.ValidationError.duplicateTitle)
    }

    @Test("rename renames the folder + updates in-memory entry")
    func rename() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try await ContextCRUDChecks.assertRename(
            AreaManager(nexus: nexus), in: nexus, from: "Personal", to: "Life",
            folderURL: NexusPaths.areaFolderURL(forTitle:in:))
    }

    @Test("delete removes folder + drops from areas")
    func delete() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try await ContextCRUDChecks.assertDelete(
            AreaManager(nexus: nexus), in: nexus, named: "Personal",
            folderURL: NexusPaths.areaFolderURL(forTitle:in:))
    }

    @Test("loadAll reads existing _area.json folders")
    func loadExisting() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.areaFolderURL(forTitle: "Pre-existing", in: nexus)
        let meta = NexusPaths.areaMetadataURL(forTitle: "Pre-existing", in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Area(id: "01H", title: "Pre-existing", icon: nil, blocks: [], modifiedAt: Date())
            .save(to: meta)

        let manager = AreaManager(nexus: nexus)
        await manager.loadAll()
        #expect(manager.areas.count == 1)
        #expect(manager.areas.first?.title == "Pre-existing")
    }
}
