import Testing
import Foundation
@testable import Pommora

@Suite struct ItemTemplateConfigTests {
    @Test func fullConfigRoundTrips() throws {
        let c = ItemTemplateConfig(
            layout: .gallery,
            promotedProperties: [PromotedProperty(id: "p1", display: .banner)],
            coverPropertyID: "p1", descriptionCap: 250, defaultDescription: "seed")
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(ItemTemplateConfig.self, from: data) == c)
    }
    @Test func legacyLayoutStringStillDecodes() throws {
        let json = #"{"layout":"standard"}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(ItemTemplateConfig.self, from: json).layout == .standard)
    }
    @Test func itemTypeWithNilTemplateRoundTrips() throws {  // back-compat guard
        let t = ItemType(id: "01H", title: "T", icon: nil, properties: [], views: [], modifiedAt: .init(timeIntervalSince1970: 0))
        let data = try JSONEncoder().encode(t)
        #expect(try JSONDecoder().decode(ItemType.self, from: data).templateConfig == nil)
    }
}
