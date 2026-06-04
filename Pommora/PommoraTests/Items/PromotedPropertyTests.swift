import Testing
import Foundation
@testable import Pommora

@Suite struct PromotedPropertyTests {
    @Test func promotedRoundTripsWithAndWithoutDisplay() throws {
        let a = PromotedProperty(id: "prop_1", display: .thumbnail)
        let b = PromotedProperty(id: "prop_2", display: nil)
        for p in [a, b] {
            let data = try JSONEncoder().encode(p)
            #expect(try JSONDecoder().decode(PromotedProperty.self, from: data) == p)
        }
    }
    @Test func displayUnknownPreserved() throws {
        let p = PromotedProperty(id: "p", display: .unknown("carousel"))
        let data = try JSONEncoder().encode(p)
        #expect(try JSONDecoder().decode(PromotedProperty.self, from: data).display == .unknown("carousel"))
    }
    @Test func promotedOmitsNilDisplayKey() throws {
        let json = String(data: try JSONEncoder().encode(PromotedProperty(id: "p", display: nil)), encoding: .utf8)!
        #expect(!json.contains("display"))
    }
}
