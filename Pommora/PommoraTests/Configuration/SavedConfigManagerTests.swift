import Foundation
import Testing
@testable import Pommora

@MainActor
@Suite("SavedConfigManager")
struct SavedConfigManagerTests {

    @Test("load seeds three fixed items")
    func seeds() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = SavedConfigManager(nexus: nexus)
        await m.load()
        #expect(m.config.items.map(\.key) == ["homepage", "calendar", "recents"])
    }

    @Test("save persists label edits")
    func save() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = SavedConfigManager(nexus: nexus)
        await m.load()
        m.config.items[0].label = "Dashboard"
        try await m.save()
        let reloaded = try AtomicJSON.decode(SavedConfig.self, from: NexusPaths.savedConfigURL(in: nexus))
        #expect(reloaded.items[0].label == "Dashboard")
    }
}
