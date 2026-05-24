import Foundation
import Testing
@testable import Pommora

/// Verifies the EC2 `schema_version: 1` forward-compat field on all four
/// non-Agenda sidecars (PageType, PageCollection, ItemType, ItemCollection).
/// AgendaTaskSchema + AgendaEventSchema were already on `schemaVersion: 1`
/// (camelCase on-disk key, pre-existing convention) — those are not retested
/// here; their existing tests already cover round-trip.
@Suite("SidecarVersion") struct SidecarVersionTests {

    // MARK: - PageType

    @Test func pageTypeFreshDefaultsToSchemaVersion1() throws {
        let pt = PageType(
            id: "01HP", title: "X", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        #expect(pt.schemaVersion == 1)
    }

    @Test func pageTypeEncodesSchemaVersionKey() throws {
        let pt = PageType(
            id: "01HP", title: "X", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let data = try AtomicJSON.encode(pt)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""schema_version" : 1"#))
    }

    @Test func pageTypeLegacyDecodeDefaultsToZero() throws {
        let json = #"""
        {
          "id": "01HP",
          "icon": null,
          "modified_at": "2026-05-24T00:00:00Z",
          "properties": [],
          "views": []
        }
        """#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pt = try decoder.decode(PageType.self, from: json)
        #expect(pt.schemaVersion == 0)
    }

    // MARK: - PageCollection

    @Test func pageCollectionFreshDefaultsToSchemaVersion1() {
        let pc = PageCollection(
            id: "01HC", typeID: "01HP", title: "X",
            folderURL: URL(fileURLWithPath: "/tmp"), modifiedAt: Date()
        )
        #expect(pc.schemaVersion == 1)
    }

    @Test func pageCollectionLegacyDecodeDefaultsToZero() throws {
        let json = #"""
        {
          "id": "01HC",
          "type_id": "01HP",
          "modified_at": "2026-05-24T00:00:00Z"
        }
        """#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pc = try decoder.decode(PageCollection.self, from: json)
        #expect(pc.schemaVersion == 0)
    }

    // MARK: - ItemType

    @Test func itemTypeFreshDefaultsToSchemaVersion1() {
        let it = ItemType(
            id: "01HI", title: "X", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        #expect(it.schemaVersion == 1)
    }

    @Test func itemTypeEncodesSchemaVersionKey() throws {
        let it = ItemType(
            id: "01HI", title: "X", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let data = try AtomicJSON.encode(it)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""schema_version" : 1"#))
    }

    @Test func itemTypeLegacyDecodeDefaultsToZero() throws {
        let json = #"""
        {
          "id": "01HI",
          "icon": null,
          "modified_at": "2026-05-24T00:00:00Z",
          "properties": [],
          "views": []
        }
        """#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let it = try decoder.decode(ItemType.self, from: json)
        #expect(it.schemaVersion == 0)
    }

    // MARK: - ItemCollection

    @Test func itemCollectionFreshDefaultsToSchemaVersion1() {
        let ic = ItemCollection(
            id: "01HIC", typeID: "01HI", title: "X",
            folderURL: URL(fileURLWithPath: "/tmp"), modifiedAt: Date()
        )
        #expect(ic.schemaVersion == 1)
    }

    @Test func itemCollectionLegacyDecodeDefaultsToZero() throws {
        let json = #"""
        {
          "id": "01HIC",
          "type_id": "01HI",
          "modified_at": "2026-05-24T00:00:00Z"
        }
        """#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let ic = try decoder.decode(ItemCollection.self, from: json)
        #expect(ic.schemaVersion == 0)
    }

    // MARK: - Round-trip preserves version

    @Test func pageTypeRoundTripPreservesSchemaVersion() throws {
        var pt = PageType(
            id: "01HP", title: "X", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        pt.schemaVersion = 5  // future version
        let data = try AtomicJSON.encode(pt)
        let decoded = try AtomicJSON.decode(PageType.self, from: writeToTemp(data: data))
        #expect(decoded.schemaVersion == 5)
    }

    /// Helper: write JSON bytes to a temp file (AtomicJSON.decode takes a URL).
    private func writeToTemp(data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pommora-sidecar-version-test-\(UUID().uuidString).json")
        try data.write(to: url, options: [.atomic])
        return url
    }
}
