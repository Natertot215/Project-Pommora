import Foundation
import Testing
@testable import Pommora

@Suite("PropertyGroupingCodableTests") struct PropertyGroupingCodableTests {
    @Test("enums round-trip via raw value")
    func enumRawValues() {
        #expect(GroupOrderMode.configured.rawValue == "configured")
        #expect(GroupOrderMode.reversed.rawValue == "reversed")
        #expect(GroupOrderMode.manual.rawValue == "manual")
        #expect(DateGranularity.week.rawValue == "week")
        #expect(EmptyPlacement.bottom.rawValue == "bottom")
    }

    @Test("legacy {property_id, order} decodes with safe defaults")
    func legacyDecode() throws {
        let json = #"{"property_id":"prop_x","order":["a","b"]}"#.data(using: .utf8)!
        let g = try JSONDecoder().decode(PropertyGrouping.self, from: json)
        #expect(g.propertyID == "prop_x")
        #expect(g.order == ["a","b"])
        #expect(g.orderMode == .configured)
        #expect(g.emptyPlacement == .bottom)
        #expect(g.hideEmptyGroups == false)
        #expect(g.dateGranularity == nil)
    }

    @Test("full round-trip preserves every field")
    func fullRoundTrip() throws {
        let g = PropertyGrouping(propertyID: "p", orderMode: .manual, order: ["x"],
                                 dateGranularity: .month, emptyPlacement: .top, hideEmptyGroups: true)
        let data = try JSONEncoder().encode(g)
        let back = try JSONDecoder().decode(PropertyGrouping.self, from: data)
        #expect(back == g)
    }
}
