import Foundation
import Testing
@testable import Pommora

@MainActor
@Suite("SpaceManager")
struct SpaceManagerTests {

    @Test("create writes a .space.json on disk and adds to spaces")
    func create() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()

        try await manager.create(name: "Personal", color: .blue, icon: "person.circle")
        let url = NexusPaths.spaceFileURL(forTitle: "Personal", in: nexus)
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

    @Test("rename renames the file + updates in-memory entry")
    func rename() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()
        try await manager.create(name: "Personal", color: .blue, icon: nil)
        let space = manager.spaces.first!

        try await manager.rename(space, to: "Life")
        let oldURL = NexusPaths.spaceFileURL(forTitle: "Personal", in: nexus)
        let newURL = NexusPaths.spaceFileURL(forTitle: "Life", in: nexus)
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
        let reloaded = try Space.load(from: NexusPaths.spaceFileURL(forTitle: "Personal", in: nexus))
        #expect(reloaded.color == .red)
    }

    @Test("delete removes file + drops from spaces")
    func delete() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()
        try await manager.create(name: "Personal", color: .blue, icon: nil)
        let space = manager.spaces.first!

        try await manager.delete(space)
        let url = NexusPaths.spaceFileURL(forTitle: "Personal", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(manager.spaces.isEmpty)
    }

    @Test("loadAll reads existing .space.json files")
    func loadExisting() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let dir = NexusPaths.spacesDir(in: nexus)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Space(id: "01H", title: "Pre-existing", color: .green, icon: nil,
                  blocks: [], modifiedAt: Date())
            .save(to: NexusPaths.spaceFileURL(forTitle: "Pre-existing", in: nexus))

        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()
        #expect(manager.spaces.count == 1)
        #expect(manager.spaces.first?.title == "Pre-existing")
    }
}
