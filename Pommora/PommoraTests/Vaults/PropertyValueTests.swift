import Foundation
import Testing

@testable import Pommora

@Suite("PropertyValue")
struct PropertyValueTests {

    @Test("round-trips a dictionary of every type")
    func roundTripDictionary() throws {
        // `.date` is calendar-day precision (yyyy-MM-dd, UTC) — seed at midnight UTC
        // so the truncating encoder round-trips equal. `.datetime` keeps full ISO-8601.
        let midnightUTC = Date(timeIntervalSince1970: 1716422400)  // 2024-05-23 00:00:00 UTC
        let original: [String: PropertyValue] = [
            "count": .number(42.5),
            "done": .checkbox(true),
            "due": .date(midnightUTC),
            "kickoff": .datetime(Date(timeIntervalSince1970: 1716480000)),
            "status": .select("Active"),
            "tags": .multiSelect(["urgent", "review"]),
            "link": .url(URL(string: "https://example.com")!),
            "relatedItem": .relation(["01HTARGET"]),
            "missing": .null,
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([String: PropertyValue].self, from: data)
        #expect(decoded.count == original.count)
        for (k, v) in original {
            #expect(decoded[k] == v, "mismatch on key \(k)")
        }
    }

    @Test("relation encodes as an array of tagged $rel objects")
    func relationEncodesAsArrayOfTaggedObjects() throws {
        let data = try JSONEncoder().encode(PropertyValue.relation(["01A", "01B"]))
        let raw = String(data: data, encoding: .utf8)!
        // Array of tagged objects, both IDs present in $rel form.
        #expect(raw == "[{\"$rel\":\"01A\"},{\"$rel\":\"01B\"}]")
    }

    @Test("relation array round-trips encode -> decode")
    func relationArrayRoundTrips() throws {
        let original = PropertyValue.relation(["01A"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PropertyValue.self, from: data)
        #expect(decoded == .relation(["01A"]))
    }

    @Test("decoder tolerates a legacy single $rel object")
    func decoderToleratesLegacySingleRelObject() throws {
        let data = "{\"$rel\":\"01A\"}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PropertyValue.self, from: data)
        #expect(decoded == .relation(["01A"]))
    }

    @Test("decoder accepts the new $rel array shape")
    func decoderAcceptsNewRelArray() throws {
        let data = "[{\"$rel\":\"01A\"},{\"$rel\":\"01B\"}]".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PropertyValue.self, from: data)
        #expect(decoded == .relation(["01A", "01B"]))
    }

    @Test("a bare string array still decodes as multiSelect, not relation")
    func bareStringArrayDecodesAsMultiSelect() throws {
        let data = "[\"a\",\"b\"]".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PropertyValue.self, from: data)
        #expect(decoded == .multiSelect(["a", "b"]))
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
        if case .date(let d) = decoded {
            #expect(abs(d.timeIntervalSince1970 - 1716422400) < 1)
        } else {
            Issue.record("expected .date case after decode, got \(decoded)")
        }
    }

    // MARK: - Phase A.2: status / file / lastEditedTime

    @Test func roundTripStatusValue() throws {
        let value: PropertyValue = .status("not_started")
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(PropertyValue.self, from: encoded)
        #expect(decoded == .status("not_started"))
    }

    @Test func roundTripFileValue() throws {
        let ref = FileRef(
            path: ".nexus/attachments/01HABC/foo.pdf",
            originalName: "foo.pdf",
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            mimeType: "application/pdf"
        )
        let value: PropertyValue = .file([ref])
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(PropertyValue.self, from: encoded)
        #expect(decoded == .file([ref]))
    }

    @Test func fileRefSnakeCaseEncoding() throws {
        let ref = FileRef(
            path: "p", originalName: "o.pdf",
            addedAt: Date(timeIntervalSince1970: 0),
            mimeType: "application/pdf"
        )
        let data = try JSONEncoder().encode(ref)
        let s = String(data: data, encoding: .utf8)!
        // JSONEncoder escapes `/` as `\/`; assert key presence only, not full MIME literal.
        #expect(s.contains(#""original_name":"o.pdf""#))
        #expect(s.contains(#""added_at""#))
        #expect(s.contains(#""mime_type""#))
        // Round-trip the MIME value to confirm correctness without literal-shape coupling.
        let decoded = try JSONDecoder().decode(FileRef.self, from: data)
        #expect(decoded.mimeType == "application/pdf")
    }

    @Test func lastEditedTimeEncodingThrows() throws {
        // .lastEditedTime is virtual — never stored. Encoding should throw.
        let value: PropertyValue = .lastEditedTime
        #expect(throws: EncodingError.self) {
            _ = try JSONEncoder().encode(value)
        }
    }
}
