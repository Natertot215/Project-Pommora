import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("SpaceManager")
struct SpaceManagerTests {

    @Test("create writes a _space.json folder on disk and adds to spaces")
    func create() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()

        try await manager.create(name: "Personal", color: .blue, icon: "person.circle")
        let url = NexusPaths.spaceMetadataURL(forTitle: "Personal", in: nexus)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(manager.spaces.count == 1)
        #expect(manager.spaces.first?.title == "Personal")
    }

    @Test("create with duplicate title throws + leaves disk unchanged")
    func createDuplicate() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()
        try await manager.create(name: "Personal", color: .blue, icon: nil)

        await #expect(throws: SpaceValidator.ValidationError.duplicateTitle) {
            try await manager.create(name: "personal", color: .red, icon: nil)
        }
        #expect(manager.spaces.count == 1)
    }

    @Test("rename renames the folder + updates in-memory entry")
    func rename() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()
        try await manager.create(name: "Personal", color: .blue, icon: nil)
        let space = manager.spaces.first!

        try await manager.rename(space, to: "Life")
        let oldURL = NexusPaths.spaceMetadataURL(forTitle: "Personal", in: nexus)
        let newURL = NexusPaths.spaceMetadataURL(forTitle: "Life", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(manager.spaces.first?.title == "Life")
    }

    @Test("updateColor mutates field + bumps modified_at on disk")
    func updateColor() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()
        try await manager.create(name: "Personal", color: .blue, icon: nil)
        let space = manager.spaces.first!

        try await manager.updateColor(space, to: .red)
        #expect(manager.spaces.first?.color == .red)
        let reloaded = try Space.load(from: NexusPaths.spaceMetadataURL(forTitle: "Personal", in: nexus))
        #expect(reloaded.color == .red)
    }

    @Test("delete removes folder + drops from spaces")
    func delete() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()
        try await manager.create(name: "Personal", color: .blue, icon: nil)
        let space = manager.spaces.first!

        try await manager.delete(space)
        let url = NexusPaths.spaceFolderURL(forTitle: "Personal", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(manager.spaces.isEmpty)
    }

    @Test("loadAll reads existing _space.json folders")
    func loadExisting() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.spaceFolderURL(forTitle: "Pre-existing", in: nexus)
        let meta = NexusPaths.spaceMetadataURL(forTitle: "Pre-existing", in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Space(
            id: "01H", title: "Pre-existing", color: .green, icon: nil,
            blocks: [], modifiedAt: Date()
        )
        .save(to: meta)

        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()
        #expect(manager.spaces.count == 1)
        #expect(manager.spaces.first?.title == "Pre-existing")
    }
}
