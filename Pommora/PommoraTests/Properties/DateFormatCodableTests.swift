import Foundation
import Testing
@testable import Pommora

/// Coverage for the redesigned Date property display config (2026-06-02):
/// `DateFormat` (4 date-portion formats), `TimeFormat` (None/12h/24h), their
/// surfacing on `PropertyDefinition`, and the `.date`→`.datetime` type
/// normalization that retires the date-only type.
@Suite("Date display config") struct DateFormatCodableTests {
    /// 2026-03-01 15:45 local — noon-ish guard against timezone date-shift.
    private static func sampleDate() -> Date {
        Calendar.current.date(
            from: DateComponents(year: 2026, month: 3, day: 1, hour: 15, minute: 45)
        )!
    }

    // MARK: - DateFormat raw-value contract

    @Test func dateFormatRawValueRoundTrip() throws {
        let cases: [(DateFormat, String)] = [
            (.short, #""short""#),
            (.full, #""full""#),
            (.dayMonthYear, #""dayMonthYear""#),
            (.monthDayYear, #""monthDayYear""#),
        ]
        for (format, expectedJSON) in cases {
            let data = try JSONEncoder().encode(format)
            #expect(String(data: data, encoding: .utf8) == expectedJSON)
            #expect(try JSONDecoder().decode(DateFormat.self, from: data) == format)
        }
    }

    @Test func dateFormatLegacyValuesMigrate() throws {
        let cases: [(String, DateFormat)] = [
            ("monthDayLong", .short),
            ("monthDayYearLong", .full),
            ("numericShort", .monthDayYear),
            ("numericMedium", .monthDayYear),
            ("numericLong", .monthDayYear),
            ("iso", .full),
            ("long", .full),  // interim 2026-06-02 raw value, renamed to .full
        ]
        for (legacyRaw, expected) in cases {
            let json = "\"\(legacyRaw)\"".data(using: .utf8)!
            #expect(try JSONDecoder().decode(DateFormat.self, from: json) == expected)
        }
    }

    @Test func dateFormatUnknownFallsBackToFull() throws {
        let json = #""garbage""#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(DateFormat.self, from: json) == .full)
    }

    // MARK: - DateFormat rendering

    @Test func dateFormatRendersNumericFormats() {
        let d = Self.sampleDate()
        #expect(DateFormat.dayMonthYear.string(from: d) == "01/03/2026")
        #expect(DateFormat.monthDayYear.string(from: d) == "03/01/2026")
    }

    @Test func dateFormatRendersOrdinalDay() {
        let d = Self.sampleDate()
        // Month + weekday names are locale-dependent; the ordinal suffix is
        // hard-coded English, and Full Date carries a weekday + comma + year.
        #expect(DateFormat.short.string(from: d).contains("1st"))
        let full = DateFormat.full.string(from: d)
        #expect(full.contains("1st"))
        #expect(full.contains("2026"))
        #expect(full.contains(","))  // "<Weekday>, March 1st 2026"
    }

    // MARK: - TimeFormat

    @Test func timeFormatRawValueRoundTrip() throws {
        let cases: [(TimeFormat, String)] = [
            (.none, #""none""#),
            (.twelveHour, #""twelveHour""#),
            (.twentyFourHour, #""twentyFourHour""#),
        ]
        for (format, expectedJSON) in cases {
            let data = try JSONEncoder().encode(format)
            #expect(String(data: data, encoding: .utf8) == expectedJSON)
            #expect(try JSONDecoder().decode(TimeFormat.self, from: data) == format)
        }
    }

    @Test func timeFormatShowsTime() {
        #expect(TimeFormat.none.showsTime == false)
        #expect(TimeFormat.twelveHour.showsTime == true)
        #expect(TimeFormat.twentyFourHour.showsTime == true)
    }

    @Test func timeFormatRenders() {
        let d = Self.sampleDate()
        #expect(TimeFormat.none.string(from: d) == nil)
        #expect(TimeFormat.twentyFourHour.string(from: d) == "15:45")
        #expect(TimeFormat.twelveHour.string(from: d)?.contains("3:45") == true)
    }

    // MARK: - PropertyDefinition surfacing

    @Test func propertyDefinitionRoundTripWithTimeFormat() throws {
        let def = PropertyDefinition(id: "prop_01H", name: "Due", type: .datetime, timeFormat: .twelveHour)
        let data = try JSONEncoder().encode(def)
        #expect(String(data: data, encoding: .utf8)!.contains(#""time_format":"twelveHour""#))
        let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: data)
        #expect(decoded.timeFormat == .twelveHour)
    }

    @Test func propertyDefinitionOmitsTimeFormatWhenNil() throws {
        let def = PropertyDefinition(id: "prop_01H", name: "Due", type: .datetime)
        #expect(def.timeFormat == nil)
        #expect(!String(data: try JSONEncoder().encode(def), encoding: .utf8)!.contains("time_format"))
    }

    @Test func propertyDefinitionMigratesLegacyDateFormatValue() throws {
        let json = #"{"id": "p", "name": "Due", "type": "datetime", "date_format": "numericLong"}"#
            .data(using: .utf8)!
        #expect(try JSONDecoder().decode(PropertyDefinition.self, from: json).dateFormat == .monthDayYear)
    }

    // MARK: - Date-only type retirement

    @Test func dateTypeNormalizesToDatetimeOnDecode() throws {
        // A pre-retirement date-only schema loads as the unified `.datetime`.
        let json = #"{"id": "p", "name": "Due", "type": "date"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: json)
        #expect(decoded.type == .datetime)
        #expect(decoded.timeFormat == nil)  // nil = .none → date-only display preserved
    }

    @Test func datetimeTypeDecodesUnchanged() throws {
        let json = #"{"id": "p", "name": "Due", "type": "datetime"}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(PropertyDefinition.self, from: json).type == .datetime)
    }
}
