import Foundation
import Testing

@testable import Pommora

@Suite("TierConfig")
struct TierConfigTests {

    @Test("default seed has Area/Topic/Project labels and color tagging")
    func defaultSeed() {
        let config = TierConfig.defaultSeed()
        #expect(config.schemaVersion == 1)
        #expect(config.tiers.count == 3)
        #expect(config.tiers[0].level == 1)
        #expect(config.tiers[0].singular == "Area")
        #expect(config.tiers[0].plural == "Areas")
        #expect(config.tiers[1].level == 2)
        #expect(config.tiers[1].singular == "Topic")
        #expect(config.tiers[2].level == 3)
        #expect(config.tiers[2].singular == "Project")
        #expect(config.taggingStyle == .color)
        for tier in config.tiers { #expect(tier.exposed == true) }
    }

    @Test("Codable round-trip")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent(".nexus/tier-config.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let original = TierConfig(
            schemaVersion: 1,
            tiers: [
                TierConfig.Tier(level: 1, singular: "Area", plural: "Areas", exposed: true),
                TierConfig.Tier(level: 2, singular: "Project", plural: "Projects", exposed: true),
                TierConfig.Tier(level: 3, singular: "Sub-project", plural: "Sub-projects", exposed: false),
            ],
            taggingStyle: .both
        )
        try AtomicJSON.write(original, to: url)
        let loaded = try AtomicJSON.decode(TierConfig.self, from: url)
        #expect(loaded == original)
    }

    @Test("on-disk JSON uses snake_case for tagging_style")
    func snakeCaseKey() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("tc.json")

        try AtomicJSON.write(TierConfig.defaultSeed(), to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("\"tagging_style\""))
        #expect(raw.contains("\"schemaVersion\""))  // version field stays camelCase per existing convention
    }
}
