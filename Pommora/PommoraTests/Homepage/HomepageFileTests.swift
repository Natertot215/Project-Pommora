import Foundation
import Testing

@testable import Pommora

@Suite("HomepageFile")
struct HomepageFileTests {

    @Test("Homepage round-trips")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("homepage.json")

        let original = Homepage(
            schemaVersion: 1,
            icon: "house",
            blocks: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try AtomicJSON.write(original, to: url)
        let loaded = try AtomicJSON.decode(Homepage.self, from: url)
        #expect(loaded == original)
    }

    @Test("defaultSeed has house icon + empty blocks")
    func defaultSeed() {
        let seed = Homepage.defaultSeed()
        #expect(seed.schemaVersion == 1)
        #expect(seed.icon == "house")
        #expect(seed.blocks == [])
    }
}
