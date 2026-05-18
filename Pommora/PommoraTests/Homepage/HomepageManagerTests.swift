import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("HomepageManager")
struct HomepageManagerTests {

    @Test("load seeds homepage.json if missing")
    func seeds() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = HomepageManager(nexus: nexus)
        await manager.load()
        let url = NexusPaths.homepageURL(in: nexus)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(manager.homepage.icon == "house")
    }

    @Test("load reads existing homepage.json")
    func loadExisting() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.homepageURL(in: nexus)
        try AtomicJSON.write(
            Homepage(
                schemaVersion: 1, icon: "bookmark", blocks: [],
                modifiedAt: Date(timeIntervalSince1970: 1716480000)),
            to: url
        )
        let manager = HomepageManager(nexus: nexus)
        await manager.load()
        #expect(manager.homepage.icon == "bookmark")
    }

    @Test("save persists changes")
    func save() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = HomepageManager(nexus: nexus)
        await manager.load()
        manager.homepage.icon = "star"
        try await manager.save()
        let reloaded = try AtomicJSON.decode(Homepage.self, from: NexusPaths.homepageURL(in: nexus))
        #expect(reloaded.icon == "star")
    }
}
