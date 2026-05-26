import Foundation
import Testing
@testable import Pommora

/// Codable + round-trip coverage for the upgraded `SavedView` shape and its
/// reserved Codable stubs `SortCriterion` / `FilterGroup` / `GroupConfig`
/// (Task 3, Phase A — v0.3.1).
///
/// Backwards-compatibility note: the previous SavedView was the empty
/// `struct SavedView {}` stub. Empty `{}` from an earlier encode must still
/// decode cleanly (defensive defaults on every field). Task 5's `loadAll`
/// default-view migration replaces any container whose `views` is empty.
@Suite("SavedView + reserved Codable stubs") struct SavedViewCodableTests {
    // MARK: - SavedView round-trip

    @Test func fullySpecifiedRoundTrip() throws {
        let view = SavedView(
            id: "view_01HVIEW",
            name: "All Books",
            icon: "books.vertical",
            type: .table,
            visibleProperties: ["prop_01HAUTHOR", "prop_01HYEAR"],
            hiddenProperties: ["prop_01HISBN"]
        )
        let data = try JSONEncoder().encode(view)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""id":"view_01HVIEW""#))
        #expect(s.contains(#""visible_properties":["prop_01HAUTHOR","prop_01HYEAR"]"#))
        #expect(s.contains(#""hidden_properties":["prop_01HISBN"]"#))
        #expect(s.contains(#""type":"table""#))

        let decoded = try JSONDecoder().decode(SavedView.self, from: data)
        #expect(decoded == view)
    }

    @Test func decodingMissingReservedStubsKeepsThemNil() throws {
        let json = #"""
        {
          "id": "view_01HVIEW",
          "name": "Table",
          "icon": "tablecells",
          "type": "table",
          "visible_properties": [],
          "hidden_properties": []
        }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SavedView.self, from: json)
        #expect(decoded.sort == nil)
        #expect(decoded.filter == nil)
        #expect(decoded.group == nil)
    }

    @Test func decodingEmptyObjectFallsBackToSafeDefaults() throws {
        // Pre-v0.3.1 sidecars may have an empty `{}` left over from the empty
        // stub. Defensive decode keeps the load path crash-free; Task 5's
        // default-view migration replaces the result on first loadAll.
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SavedView.self, from: json)
        #expect(decoded.id == "")
        #expect(decoded.name == "Table")
        #expect(decoded.type == .table)
        #expect(decoded.visibleProperties.isEmpty)
        #expect(decoded.hiddenProperties.isEmpty)
    }

    @Test func defaultIconKeySerialized() throws {
        let view = SavedView(id: "view_01HVIEW")
        let data = try JSONEncoder().encode(view)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""icon":"tablecells""#))
    }

    // MARK: - ViewType cases

    @Test func viewTypeRoundTripsAllCases() throws {
        for kind in [ViewType.table, .board, .list, .cards, .gallery] {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(ViewType.self, from: data)
            #expect(decoded == kind)
        }
    }

    // MARK: - Reserved stubs round-trip

    @Test func sortCriterionRoundTrip() throws {
        let crit = SortCriterion(propertyID: "prop_01HXY", direction: .descending)
        let data = try JSONEncoder().encode(crit)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""property_id":"prop_01HXY""#))
        #expect(s.contains(#""direction":"descending""#))

        let decoded = try JSONDecoder().decode(SortCriterion.self, from: data)
        #expect(decoded == crit)
    }

    @Test func filterGroupRoundTrip() throws {
        let group = FilterGroup(
            match: .all,
            rules: [
                FilterRule(propertyID: "prop_01HXY", op: "equals", value: "done"),
                FilterRule(propertyID: "prop_01HABC", op: "not_empty", value: nil),
            ]
        )
        let data = try JSONEncoder().encode(group)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""match":"all""#))
        #expect(s.contains(#""property_id":"prop_01HXY""#))
        #expect(s.contains(#""op":"equals""#))

        let decoded = try JSONDecoder().decode(FilterGroup.self, from: data)
        #expect(decoded == group)
    }

    @Test func groupConfigRoundTripWithOrder() throws {
        let cfg = GroupConfig(
            propertyID: "prop_01HSTATUS",
            order: ["upcoming", "in_progress", "done"]
        )
        let data = try JSONEncoder().encode(cfg)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""property_id":"prop_01HSTATUS""#))
        #expect(s.contains(#""order":["upcoming","in_progress","done"]"#))

        let decoded = try JSONDecoder().decode(GroupConfig.self, from: data)
        #expect(decoded == cfg)
    }

    @Test func groupConfigOrderOmittedWhenNil() throws {
        let cfg = GroupConfig(propertyID: "prop_01HSTATUS", order: nil)
        let data = try JSONEncoder().encode(cfg)
        let s = String(data: data, encoding: .utf8)!
        #expect(!s.contains("\"order\""))
    }
}
