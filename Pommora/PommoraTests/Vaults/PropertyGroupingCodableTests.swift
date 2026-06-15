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
}
