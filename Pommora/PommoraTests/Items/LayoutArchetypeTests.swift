import Foundation
import Testing
@testable import Pommora

@Suite struct LayoutArchetypeTests {
    @Test func knownValuesRoundTrip() throws {
        for raw in ["compact", "standard", "banner_two_column", "gallery", "wide", "reserved"] {
            let a = LayoutArchetype(rawValue: raw)
            #expect(a.rawValue == raw)
            let data = try JSONEncoder().encode(a)
            #expect(try JSONDecoder().decode(LayoutArchetype.self, from: data) == a)
        }
    }
    @Test func unknownPreservesRawValue() throws {
        let a = LayoutArchetype(rawValue: "future_layout_v9")
        #expect(a == .unknown("future_layout_v9"))
        let data = try JSONEncoder().encode(a)
        #expect(try JSONDecoder().decode(LayoutArchetype.self, from: data).rawValue == "future_layout_v9")
    }
    @Test func selectableExcludesUnknown() {
        #expect(LayoutArchetype.selectable.count == 6)
        #expect(!LayoutArchetype.selectable.contains(.unknown("x")))
    }
}
