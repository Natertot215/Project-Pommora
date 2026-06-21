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
        let manager = AreaManager(nexus: nexus)
        await manager.loadAll()

        try await manager.create(name: "Personal", icon: "person.circle")
        let url = NexusPaths.areaMetadataURL(forTitle: "Personal", in: nexus)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(manager.areas.count == 1)
        #expect(manager.areas.first?.title == "Personal")
    }

    @Test("create with duplicate title throws + leaves disk unchanged")
    func createDuplicate() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AreaManager(nexus: nexus)
        await manager.loadAll()
        try await manager.create(name: "Personal", icon: nil)

        await #expect(throws: AreaValidator.ValidationError.duplicateTitle) {
            try await manager.create(name: "personal", icon: nil)
        }
        #expect(manager.areas.count == 1)
    }

    @Test("rename renames the folder + updates in-memory entry")
    func rename() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AreaManager(nexus: nexus)
        await manager.loadAll()
        try await manager.create(name: "Personal", icon: nil)
        let area = manager.areas.first!

        try await manager.rename(area, to: "Life")
        let oldURL = NexusPaths.areaMetadataURL(forTitle: "Personal", in: nexus)
        let newURL = NexusPaths.areaMetadataURL(forTitle: "Life", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(manager.areas.first?.title == "Life")
    }

    @Test("delete removes folder + drops from areas")
    func delete() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AreaManager(nexus: nexus)
        await manager.loadAll()
        try await manager.create(name: "Personal", icon: nil)
        let area = manager.areas.first!

        try await manager.delete(area)
        let url = NexusPaths.areaFolderURL(forTitle: "Personal", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(manager.areas.isEmpty)
    }

    @Test("loadAll reads existing _area.json folders")
    func loadExisting() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.areaFolderURL(forTitle: "Pre-existing", in: nexus)
        let meta = NexusPaths.areaMetadataURL(forTitle: "Pre-existing", in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Area(
            id: "01H", title: "Pre-existing", icon: nil,
            blocks: [], modifiedAt: Date()
        )
        .save(to: meta)

        let manager = AreaManager(nexus: nexus)
        await manager.loadAll()
        #expect(manager.areas.count == 1)
        #expect(manager.areas.first?.title == "Pre-existing")
    }
}
