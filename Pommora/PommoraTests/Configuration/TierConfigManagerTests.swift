import Foundation
import Testing
@testable import Pommora

@MainActor
@Suite("TierConfigManager")
struct TierConfigManagerTests {

    @Test("load seeds default on first run")
    func seeds() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = TierConfigManager(nexus: nexus)
        await m.load()
        #expect(FileManager.default.fileExists(atPath: NexusPaths.tierConfigURL(in: nexus).path))
        #expect(m.config.tiers.count == 3)
        #expect(m.config.tiers[0].singular == "Space")
    }

    @Test("save persists user edits")
    func save() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = TierConfigManager(nexus: nexus)
        await m.load()
        m.config.tiers[0].singular = "Area"
        m.config.tiers[0].plural = "Areas"
        try await m.save()
        let reloaded = try AtomicJSON.decode(TierConfig.self, from: NexusPaths.tierConfigURL(in: nexus))
        #expect(reloaded.tiers[0].singular == "Area")
    }
}
