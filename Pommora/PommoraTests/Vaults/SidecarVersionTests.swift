import Foundation
import Testing
@testable import Pommora

/// Verifies the EC2 `schema_version` forward-compat field on the non-Agenda
/// sidecars (PageCollection, PageSet). PageCollection is stamped `2`
/// (Relations-redesign re-migration bump); PageSet stays on `1` (no
/// schema change). Legacy sidecars still decode missing versions as `0`.
/// AgendaTaskSchema + AgendaEventSchema were already on `schemaVersion: 1`
/// (camelCase on-disk key, pre-existing convention) — those are not retested
/// here; their existing tests already cover round-trip.
@Suite("SidecarVersion") struct SidecarVersionTests {

    // MARK: - PageCollection

    @Test func pageTypeFreshDefaultsToSchemaVersion2() throws {
        let pt = PageCollection(
            id: "01HP", title: "X", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        #expect(pt.schemaVersion == 2)
    }

    @Test func pageTypeEncodesSchemaVersionKey() throws {
        let pt = PageCollection(
            id: "01HP", title: "X", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let data = try AtomicJSON.encode(pt)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""schema_version" : 2"#))
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
        let pt = try decoder.decode(PageCollection.self, from: json)
        #expect(pt.schemaVersion == 0)
    }

    // MARK: - PageSet

    @Test func pageCollectionFreshDefaultsToSchemaVersion1() {
        let pc = PageSet(
            id: "01HC", parentID: "01HP", title: "X",
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
        let pc = try decoder.decode(PageSet.self, from: json)
        #expect(pc.schemaVersion == 0)
    }

    // MARK: - Round-trip preserves version

    @Test func pageTypeRoundTripPreservesSchemaVersion() throws {
        var pt = PageCollection(
            id: "01HP", title: "X", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        pt.schemaVersion = 5  // future version
        let data = try AtomicJSON.encode(pt)
        let decoded = try AtomicJSON.decode(PageCollection.self, from: writeToTemp(data: data))
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
