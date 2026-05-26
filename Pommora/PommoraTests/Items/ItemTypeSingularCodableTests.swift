import Foundation
import Testing
@testable import Pommora

/// Codable + round-trip coverage for the optional `ItemType.singular` field
/// (Task 2, Phase A — v0.3.1).
///
/// `singular` is persisted as the bare `singular` key. nil falls back to the
/// `title` (folder name) at every consumer call site. Item Types only —
/// Pages aren't renameable concepts (locked decision #11).
@Suite("ItemType.singular") struct ItemTypeSingularCodableTests {
    private func makeType(singular: String? = nil) -> ItemType {
        ItemType(
            id: "01HITEMTYPE",
            title: "Books",
            icon: "books.vertical",
            properties: [],
            views: [],
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            singular: singular
        )
    }

    @Test func roundTripWithSingularPopulated() throws {
        let type = makeType(singular: "Book")
        let data = try JSONEncoder().encode(type)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""singular":"Book""#))

        let decoded = try JSONDecoder().decode(ItemType.self, from: data)
        #expect(decoded.singular == "Book")
    }

    @Test func omitsSingularKeyWhenNil() throws {
        let type = makeType(singular: nil)
        #expect(type.singular == nil)
        let data = try JSONEncoder().encode(type)
        let s = String(data: data, encoding: .utf8)!
        #expect(!s.contains("\"singular\""))
    }

    @Test func decodesMissingSingularKeyAsNil() throws {
        // Pre-v0.3.1 sidecars predate the field — round-trip must keep them as nil.
        let json = #"""
        {
            "id": "01HITEMTYPE",
            "icon": "books.vertical",
            "properties": [],
            "views": [],
            "modified_at": "2026-03-04T00:00:00Z",
            "schema_version": 1
        }
        """#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ItemType.self, from: json)
        #expect(decoded.singular == nil)
    }
}
