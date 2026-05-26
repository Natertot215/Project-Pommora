import Foundation
import Testing
@testable import Pommora

/// Codable + round-trip coverage for `DateFormat` and its surfacing as the
/// optional `PropertyDefinition.dateFormat` field (Task 1, Phase A — v0.3.1).
///
/// `dateFormat` is persisted as snake-case `date_format`. nil = default
/// (`.monthDayYearLong`); only Date / Date & Time property types read it.
@Suite("DateFormat + PropertyDefinition.dateFormat") struct DateFormatCodableTests {
    // MARK: - Raw-value round-trip

    @Test func monthDayLongRawValueRoundTrip() throws {
        let format = DateFormat.monthDayLong
        let data = try JSONEncoder().encode(format)
        #expect(String(data: data, encoding: .utf8) == #""monthDayLong""#)
        let decoded = try JSONDecoder().decode(DateFormat.self, from: data)
        #expect(decoded == .monthDayLong)
    }

    @Test func monthDayYearLongRawValueRoundTrip() throws {
        let format = DateFormat.monthDayYearLong
        let data = try JSONEncoder().encode(format)
        #expect(String(data: data, encoding: .utf8) == #""monthDayYearLong""#)
        let decoded = try JSONDecoder().decode(DateFormat.self, from: data)
        #expect(decoded == .monthDayYearLong)
    }

    @Test func numericShortRawValueRoundTrip() throws {
        let format = DateFormat.numericShort
        let data = try JSONEncoder().encode(format)
        #expect(String(data: data, encoding: .utf8) == #""numericShort""#)
        let decoded = try JSONDecoder().decode(DateFormat.self, from: data)
        #expect(decoded == .numericShort)
    }

    @Test func numericMediumRawValueRoundTrip() throws {
        let format = DateFormat.numericMedium
        let data = try JSONEncoder().encode(format)
        #expect(String(data: data, encoding: .utf8) == #""numericMedium""#)
        let decoded = try JSONDecoder().decode(DateFormat.self, from: data)
        #expect(decoded == .numericMedium)
    }

    @Test func numericLongRawValueRoundTrip() throws {
        let format = DateFormat.numericLong
        let data = try JSONEncoder().encode(format)
        #expect(String(data: data, encoding: .utf8) == #""numericLong""#)
        let decoded = try JSONDecoder().decode(DateFormat.self, from: data)
        #expect(decoded == .numericLong)
    }

    @Test func isoRawValueRoundTrip() throws {
        let format = DateFormat.iso
        let data = try JSONEncoder().encode(format)
        #expect(String(data: data, encoding: .utf8) == #""iso""#)
        let decoded = try JSONDecoder().decode(DateFormat.self, from: data)
        #expect(decoded == .iso)
    }

    // MARK: - PropertyDefinition.dateFormat round-trip

    @Test func propertyDefinitionRoundTripWithDateFormatISO() throws {
        let def = PropertyDefinition(
            id: "prop_01HDATE",
            name: "Due",
            type: .date,
            dateFormat: .iso
        )
        let data = try JSONEncoder().encode(def)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""date_format":"iso""#))
        let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: data)
        #expect(decoded == def)
        #expect(decoded.dateFormat == .iso)
    }

    @Test func propertyDefinitionOmitsDateFormatKeyWhenNil() throws {
        let def = PropertyDefinition(id: "prop_01HDATE", name: "Due", type: .date)
        #expect(def.dateFormat == nil)
        let data = try JSONEncoder().encode(def)
        let s = String(data: data, encoding: .utf8)!
        #expect(!s.contains("\"date_format\""))
    }

    @Test func propertyDefinitionDecodesMissingDateFormatKeyAsNil() throws {
        // Pre-v0.3.1 sidecars predate the field — round-trip must keep them as nil.
        let json = #"{"id": "prop_01HDATE", "name": "Due", "type": "date"}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: json)
        #expect(decoded.dateFormat == nil)
    }
}
