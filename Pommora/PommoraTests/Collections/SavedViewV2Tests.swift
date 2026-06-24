import Foundation
import Testing

@testable import Pommora

@Suite("SavedViewV2Tests")
struct SavedViewV2Tests {
    @Test func legacyVisiblePropertiesMigratesToPropertyOrder() throws {
        let json =
            #"{"id":"view_01X","name":"Table","type":"table","visible_properties":["p1","p2"],"hidden_properties":["p3"]}"#
        let v = try JSONDecoder().decode(SavedView.self, from: Data(json.utf8))
        #expect(v.propertyOrder == ["_title", "p1", "p2"])
        #expect(v.hiddenProperties == ["p3"])
        #expect(v.showCover != true)  // absent → not shown (default OFF)
    }

    @Test func encodeWritesNewKeysOnly() throws {
        var v = SavedView.defaultTable(visiblePropertyIDs: ["p1"])
        v.hiddenProperties = ["p3"]
        v.columnWidths = ["_title": 240]
        v.collapsedGroups = ["g1"]
        v.cardSize = .large
        v.showCover = true
        let data = try JSONEncoder().encode(v)
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["property_order"] != nil)
        #expect(obj["visible_properties"] == nil)
        #expect((obj["hidden_properties"] as? [String]) == ["p3"])
        #expect((obj["column_widths"] as? [String: Double])?["_title"] == 240)
        #expect(obj["card_size"] as? String == "large")
        #expect(obj["show_cover"] as? Bool == true)
    }

    @Test func cardSizeColumns() {
        #expect(CardSize.small.columnsPerRow == 8)
        #expect(CardSize.medium.columnsPerRow == 6)
        #expect(CardSize.large.columnsPerRow == 4)
    }

    @Test func defaultTableMintsTitleFirst() {
        let v = SavedView.defaultTable(visiblePropertyIDs: ["a", "b"])
        #expect(v.propertyOrder == ["_title", "a", "b"])
        #expect(v.type == .table)
    }

    @Test func titleIsReserved() {
        #expect(ReservedPropertyID.title == "_title")
        #expect(ReservedPropertyID.all.contains("_title"))
    }
}
