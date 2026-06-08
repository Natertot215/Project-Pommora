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

    // MARK: - property_layout (A4: additive, forward-compatible)

    /// Absent key ⇒ decodes to nil (additivity) and read-time default is `.standard`.
    @Test func propertyLayoutAbsentIsNilAndDefaultsStandard() throws {
        let json = #"{"description_cap":250}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ItemTemplateConfig.self, from: json)
        #expect(decoded.propertyLayout == nil)
        #expect((decoded.propertyLayout ?? .standard) == .standard)
    }

    /// `.compact` writes the on-disk key and round-trips back.
    @Test func propertyLayoutCompactRoundTripsViaKey() throws {
        var c = ItemTemplateConfig()
        c.propertyLayout = .compact
        let data = try JSONEncoder().encode(c)
        let raw = String(decoding: data, as: UTF8.self)
        #expect(raw.contains(#""property_layout":"compact""#) || raw.contains(#""property_layout" : "compact""#))
        #expect(try JSONDecoder().decode(ItemTemplateConfig.self, from: data).propertyLayout == .compact)
    }

    /// Unrecognized on-disk value is tolerated (no decode failure, no data loss).
    @Test func propertyLayoutUnknownTolerated() throws {
        let json = #"{"property_layout":"weird"}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(ItemTemplateConfig.self, from: json).propertyLayout == .unknown("weird"))
    }

    /// nil ⇒ the key is omitted on encode, proving old files stay byte-stable.
    @Test func propertyLayoutNilOmitsKey() throws {
        let data = try JSONEncoder().encode(ItemTemplateConfig())
        let raw = String(decoding: data, as: UTF8.self)
        #expect(!raw.contains("property_layout"))
    }
}
