import Foundation
import Testing
@testable import Pommora

/// Codable + round-trip coverage for `DisplayVariant` and its surfacing as the
/// optional `PropertyDefinition.displayAs` field (Task 1, Phase A — v0.3.1).
///
/// `displayAs` is persisted as snake-case `display_as`. nil = type default
/// (`.box` for Status); other property types ignore the field entirely.
@Suite("DisplayVariant + PropertyDefinition.displayAs") struct DisplayVariantCodableTests {
    // MARK: - Raw-value round-trip

    @Test func boxRawValueRoundTrip() throws {
        let variant = DisplayVariant.box
        let data = try JSONEncoder().encode(variant)
        #expect(String(data: data, encoding: .utf8) == #""box""#)
        let decoded = try JSONDecoder().decode(DisplayVariant.self, from: data)
        #expect(decoded == .box)
    }

    @Test func selectRawValueRoundTrip() throws {
        let variant = DisplayVariant.select
        let data = try JSONEncoder().encode(variant)
        #expect(String(data: data, encoding: .utf8) == #""select""#)
        let decoded = try JSONDecoder().decode(DisplayVariant.self, from: data)
        #expect(decoded == .select)
    }

    @Test func chipRawValueRoundTrip() throws {
        let variant = DisplayVariant.chip
        let data = try JSONEncoder().encode(variant)
        #expect(String(data: data, encoding: .utf8) == #""chip""#)
        let decoded = try JSONDecoder().decode(DisplayVariant.self, from: data)
        #expect(decoded == .chip)
    }

    // MARK: - PropertyDefinition.displayAs round-trip

    @Test func propertyDefinitionRoundTripWithDisplayAsSelect() throws {
        let def = PropertyDefinition(
            id: "_status",
            name: "Status",
            type: .status,
            statusGroups: PropertyDefinition.StatusGroup.defaultSeed(),
            displayAs: .select
        )
        let data = try JSONEncoder().encode(def)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""display_as":"select""#))
        let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: data)
        #expect(decoded == def)
        #expect(decoded.displayAs == .select)
    }

    @Test func propertyDefinitionOmitsDisplayAsKeyWhenNil() throws {
        let def = PropertyDefinition(id: "_status", name: "Status", type: .status)
        #expect(def.displayAs == nil)
        let data = try JSONEncoder().encode(def)
        let s = String(data: data, encoding: .utf8)!
        #expect(!s.contains("\"display_as\""))
    }

    @Test func propertyDefinitionDecodesMissingDisplayAsKeyAsNil() throws {
        // Pre-v0.3.1 sidecars predate the field — round-trip must keep them as nil.
        let json = #"{"id": "_status", "name": "Status", "type": "status"}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: json)
        #expect(decoded.displayAs == nil)
    }
}
