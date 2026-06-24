import Foundation
import Testing

@testable import Pommora

/// Codable + round-trip coverage for the `views: [SavedView]` field on
/// `PageSet` (Task 4, Phase A — v0.3.1).
///
/// Each Collection is INDEPENDENT of its parent Type — its own `views[0]`
/// config separate from the Type's. Pre-v0.3.1 sidecars predate the field
/// and must decode as `[]` so loadAll can mint a default-view migration.
@Suite("PageSet views[]") struct PageSetViewsTests {
    private func pageCollection(views: [SavedView] = []) -> PageSet {
        PageSet(
            id: "01HPC",
            parentID: "01HPT",
            title: "Drafts",
            folderURL: URL(fileURLWithPath: "/tmp/nexus/Drafts"),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            views: views
        )
    }

    private func makeView() -> SavedView {
        SavedView(
            id: "view_01HVIEW",
            name: "All",
            icon: "tablecells",
            type: .table,
            propertyOrder: ["_title", "prop_01HA"],
            hiddenProperties: []
        )
    }

    // MARK: - PageSet.views

    @Test func pageCollectionRoundTripsViews() throws {
        let c = pageCollection(views: [makeView()])
        let data = try JSONEncoder().encode(c)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""views":["#))
        #expect(s.contains(#""id":"view_01HVIEW""#))

        let decoded = try JSONDecoder().decode(PageSet.self, from: data)
        #expect(decoded.views.count == 1)
        #expect(decoded.views[0].id == "view_01HVIEW")
    }

    @Test func pageCollectionDecodesMissingViewsAsEmptyArray() throws {
        // Pre-v0.3.1 sidecar shape — no `views` key. Must round-trip as [].
        let json = #"""
            {
              "id": "01HPC",
              "type_id": "01HPT",
              "modified_at": "2026-03-04T00:00:00Z",
              "schema_version": 1
            }
            """#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PageSet.self, from: json)
        #expect(decoded.views.isEmpty)
    }

}
