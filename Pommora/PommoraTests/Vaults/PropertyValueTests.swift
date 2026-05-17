import Foundation
import Testing
@testable import Pommora

@Suite("PropertyValue")
struct PropertyValueTests {

    @Test("round-trips a dictionary of every type")
    func roundTripDictionary() throws {
        // `.date` is calendar-day precision (yyyy-MM-dd, UTC) — seed at midnight UTC
        // so the truncating encoder round-trips equal. `.datetime` keeps full ISO-8601.
        let midnightUTC = Date(timeIntervalSince1970: 1716422400) // 2024-05-23 00:00:00 UTC
        let original: [String: PropertyValue] = [
            "count": .number(42.5),
            "done": .checkbox(true),
            "due": .date(midnightUTC),
            "kickoff": .datetime(Date(timeIntervalSince1970: 1716480000)),
            "status": .select("Active"),
            "tags": .multiSelect(["urgent", "review"]),
            "link": .url(URL(string: "https://example.com")!),
            "relatedItem": .relation("01HTARGET"),
            "missing": .null
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([String: PropertyValue].self, from: data)
        #expect(decoded.count == original.count)
        for (k, v) in original {
            #expect(decoded[k] == v, "mismatch on key \(k)")
        }
    }

    @Test("relation encodes as tagged $rel object and round-trips")
    func relationTagged() throws {
        let original = PropertyValue.relation("01HTARGET")
        let data = try JSONEncoder().encode(original)
        let raw = String(data: data, encoding: .utf8)!
        #expect(raw == "{\"$rel\":\"01HTARGET\"}")
        let decoded = try JSONDecoder().decode(PropertyValue.self, from: data)
        #expect(decoded == original)
    }

    @Test("null values serialize as JSON null")
    func nullEncoding() throws {
        let value: PropertyValue = .null
        let data = try JSONEncoder().encode(value)
        let raw = String(data: data, encoding: .utf8)!
        #expect(raw == "null")
    }

    @Test("multi-select serializes as array of strings")
    func multiSelectEncoding() throws {
        let value: PropertyValue = .multiSelect(["a", "b", "c"])
        let data = try JSONEncoder().encode(value)
        let raw = String(data: data, encoding: .utf8)!
        #expect(raw == "[\"a\",\"b\",\"c\"]")
    }

    @Test("date round-trips through ISO-8601 (via outer JSONEncoder dateEncodingStrategy)")
    func dateRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // `.date` truncates to yyyy-MM-dd (UTC); seed at midnight UTC for clean round-trip.
        let original = PropertyValue.date(Date(timeIntervalSince1970: 1716422400))
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PropertyValue.self, from: data)
        if case let .date(d) = decoded {
            #expect(abs(d.timeIntervalSince1970 - 1716422400) < 1)
        } else {
            Issue.record("expected .date case after decode, got \(decoded)")
        }
    }
}
