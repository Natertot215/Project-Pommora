import Foundation
import Testing

@testable import Pommora

/// Tests for `ItemCollection.pinnedProperties` — the `pinned_properties`
/// JSON field added in Phase J.2.
///
/// Encoding choice: `pinnedProperties` is ALWAYS encoded (even when empty)
/// so freshly-written sidecars always contain the field, making later reads
/// unambiguous and avoiding a two-branch decode path in future readers.
@Suite("ItemCollectionPinningTests")
struct ItemCollectionPinningTests {

    // MARK: - Helpers

    private func makeURL() throws -> (nexus: Nexus, url: URL) {
        let nexus = try TempNexus.make()
        let folder = nexus.rootURL
            .appendingPathComponent("Errands", isDirectory: true)
            .appendingPathComponent("Pinned", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename)
        return (nexus, metaURL)
    }

    // MARK: - Test 1: round-trip with non-empty pinned list

    @Test("ItemCollection round-trips pinnedProperties through save/load")
    func roundTripNonEmpty() throws {
        let (nexus, metaURL) = try makeURL()
        defer { TempNexus.cleanup(nexus) }

        let original = ItemCollection(
            id: "01HICOLL",
            typeID: "01HITYPE",
            title: "Pinned",
            folderURL: metaURL.deletingLastPathComponent(),
            modifiedAt: Date(timeIntervalSince1970: 0),
            pinnedProperties: ["prop_abc", "prop_xyz"]
        )
        try original.save(to: metaURL)

        let loaded = try ItemCollection.load(from: metaURL)
        #expect(loaded.pinnedProperties == ["prop_abc", "prop_xyz"])
    }

    // MARK: - Test 2: legacy decode (field absent) → []

    @Test("Legacy sidecar without pinned_properties field decodes to empty array")
    func legacyDecodeDefaultsToEmpty() throws {
        let (nexus, metaURL) = try makeURL()
        defer { TempNexus.cleanup(nexus) }

        // Write a sidecar that pre-dates J.2 — no `pinned_properties` key.
        let legacyJSON = """
            {
              "id": "01HLEGACY",
              "type_id": "01HTYPE",
              "modified_at": "2026-01-01T00:00:00Z",
              "schema_version": 1
            }
            """
        try legacyJSON.write(to: metaURL, atomically: true, encoding: .utf8)

        let loaded = try ItemCollection.load(from: metaURL)
        #expect(loaded.pinnedProperties == [])
    }

    // MARK: - Test 3: encode includes pinned_properties even when empty

    @Test("Encode always includes pinned_properties key even when empty")
    func encodeIncludesFieldWhenEmpty() throws {
        let (nexus, metaURL) = try makeURL()
        defer { TempNexus.cleanup(nexus) }

        let empty = ItemCollection(
            id: "01HEMPTY",
            typeID: "01HT",
            title: "Pinned",
            folderURL: metaURL.deletingLastPathComponent(),
            modifiedAt: Date(timeIntervalSince1970: 0),
            pinnedProperties: []
        )
        try empty.save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(raw.contains("\"pinned_properties\""))
    }

    // MARK: - Test 4: ordering is preserved

    @Test("ItemCollection preserves order of pinnedProperties")
    func orderPreserved() throws {
        let (nexus, metaURL) = try makeURL()
        defer { TempNexus.cleanup(nexus) }

        let ordered = ["prop_z", "prop_a", "prop_m"]
        let original = ItemCollection(
            id: "01HORDER",
            typeID: "01HT",
            title: "Pinned",
            folderURL: metaURL.deletingLastPathComponent(),
            modifiedAt: Date(timeIntervalSince1970: 0),
            pinnedProperties: ordered
        )
        try original.save(to: metaURL)

        let loaded = try ItemCollection.load(from: metaURL)
        #expect(loaded.pinnedProperties == ordered)
    }

    // MARK: - Test 5: snake_case key on disk

    @Test("ItemCollection encodes pinnedProperties as snake_case pinned_properties")
    func snakeCaseKey() throws {
        let (nexus, metaURL) = try makeURL()
        defer { TempNexus.cleanup(nexus) }

        let col = ItemCollection(
            id: "01HSNAKE",
            typeID: "01HT",
            title: "Pinned",
            folderURL: metaURL.deletingLastPathComponent(),
            modifiedAt: Date(timeIntervalSince1970: 0),
            pinnedProperties: ["prop_x"]
        )
        try col.save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(raw.contains("\"pinned_properties\""))
        #expect(!raw.contains("\"pinnedProperties\""))
    }
}
