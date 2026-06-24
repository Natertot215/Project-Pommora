import Foundation
import Testing

@testable import Pommora

/// Decode / round-trip coverage for the discriminated `GroupConfig` value
/// (Views Task 2). Decode is lenient — a malformed or unknown shape must fall
/// back to `.structural` rather than throw, since `GroupConfig` is read as part
/// of the whole `SavedView` sidecar and a throw poisons that decode.
@Suite("GroupConfigV2Tests") struct GroupConfigV2Tests {
    private func decode(_ json: String) throws -> GroupConfig {
        try JSONDecoder().decode(GroupConfig.self, from: Data(json.utf8))
    }

    private func encodedString(_ cfg: GroupConfig) throws -> String {
        String(data: try JSONEncoder().encode(cfg), encoding: .utf8)!
    }

    // MARK: Decode cases

    @Test func decodesStructural() throws {
        #expect(try decode(#"{"kind":"structural"}"#) == .structural)
    }

    @Test func decodesProperty() throws {
        let cfg = try decode(#"{"kind":"property","property_id":"p1","order":["a"]}"#)
        #expect(cfg == .property(PropertyGrouping(propertyID: "p1", order: ["a"])))
    }

    @Test func decodesFlat() throws {
        #expect(try decode(#"{"kind":"flat"}"#) == .flat)
    }

    @Test func decodesLegacyNoKindStub() throws {
        // v0.3.1 on-disk shape: bare `property_id`, no discriminator.
        let cfg = try decode(#"{"property_id":"p1"}"#)
        #expect(cfg == .property(PropertyGrouping(propertyID: "p1", order: nil)))
    }

    @Test func unknownKindFallsBackToStructuralLeniently() throws {
        #expect(try decode(#"{"kind":"wibble"}"#) == .structural)
    }

    // MARK: Round-trip stability

    @Test func roundTripsStructural() throws {
        let s = try encodedString(.structural)
        #expect(s.contains(#""kind":"structural""#))
        #expect(try decode(s) == .structural)
    }

    @Test func roundTripsFlat() throws {
        let s = try encodedString(.flat)
        #expect(s.contains(#""kind":"flat""#))
        #expect(try decode(s) == .flat)
    }

    @Test func roundTripsPropertyWithOrder() throws {
        let cfg = GroupConfig.property(
            PropertyGrouping(propertyID: "p1", order: ["a", "b"])
        )
        let s = try encodedString(cfg)
        #expect(s.contains(#""kind":"property""#))
        #expect(s.contains(#""property_id":"p1""#))
        #expect(s.contains(#""order":["a","b"]"#))
        #expect(try decode(s) == cfg)
    }

    @Test func propertyOrderOmittedWhenNil() throws {
        let cfg = GroupConfig.property(
            PropertyGrouping(propertyID: "p1", order: nil)
        )
        let s = try encodedString(cfg)
        #expect(!s.contains("\"order\""))
        #expect(try decode(s) == cfg)
    }
}
