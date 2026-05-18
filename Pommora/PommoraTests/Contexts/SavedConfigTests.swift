import Foundation
import Testing
@testable import Pommora

@Suite("SavedConfig")
struct SavedConfigTests {

    @Test("defaultSeed has three fixed-key items in canonical order")
    func defaultSeed() {
        let cfg = SavedConfig.defaultSeed()
        #expect(cfg.schemaVersion == 1)
        #expect(cfg.items.count == 3)
        #expect(cfg.items.map(\.key) == ["homepage", "calendar", "recents"])
        #expect(cfg.items.map(\.label) == ["Homepage", "Calendar", "Recents"])
    }

    @Test("Codable round-trip preserves order + labels")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("saved.json")

        let original = SavedConfig(
            schemaVersion: 1,
            items: [
                SavedConfig.Item(key: "homepage", label: "Dashboard"),
                SavedConfig.Item(key: "calendar", label: "Schedule"),
                SavedConfig.Item(key: "recents", label: "Recent")
            ]
        )
        try AtomicJSON.write(original, to: url)
        let loaded = try AtomicJSON.decode(SavedConfig.self, from: url)
        #expect(loaded == original)
    }
}
