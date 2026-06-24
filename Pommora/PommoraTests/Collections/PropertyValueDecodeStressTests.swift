import Foundation
import Testing

@testable import Pommora

/// Stress coverage for `PropertyValue`'s shape-probing decoder — the string
/// disambiguation path, tagged-object precedence, and empty-array handling the
/// round-trip suite doesn't exercise. Decodes raw JSON to pin the probe order.
@Suite("PropertyValue decode (stress)")
struct PropertyValueDecodeStressTests {

    private func decode(_ json: String) throws -> PropertyValue {
        try JSONDecoder().decode(PropertyValue.self, from: Data(json.utf8))
    }

    // MARK: - String probe order: url -> datetime -> date -> select

    @Test("a scheme-bearing string decodes as .url")
    func urlString() throws {
        #expect(try decode("\"https://example.com\"") == .url(URL(string: "https://example.com")!))
        #expect(try decode("\"mailto:a@b.com\"") == .url(URL(string: "mailto:a@b.com")!))
    }

    @Test("a yyyy-MM-dd string decodes as .date at UTC midnight")
    func dateString() throws {
        let decoded = try decode("\"2024-05-23\"")
        guard case .date(let d) = decoded else {
            Issue.record("expected .date, got \(decoded)")
            return
        }
        #expect(d == Date(timeIntervalSince1970: 1716422400))  // 2024-05-23 00:00:00 UTC
    }

    @Test("an ISO-8601 string with time decodes as .datetime")
    func datetimeString() throws {
        let decoded = try decode("\"2024-05-23T12:00:00Z\"")
        guard case .datetime = decoded else {
            Issue.record("expected .datetime, got \(decoded)")
            return
        }
    }

    @Test("a plain string decodes as .select")
    func plainSelect() throws {
        #expect(try decode("\"hello world\"") == .select("hello world"))
    }

    @Test("a quoted number stays .select, never .number")
    func quotedNumberIsSelect() throws {
        #expect(try decode("\"42\"") == .select("42"))
    }

    @Test("an empty string decodes as .select")
    func emptyStringIsSelect() throws {
        #expect(try decode("\"\"") == .select(""))
    }

    // MARK: - Tagged-object precedence

    @Test("an object with both FileRef keys and $rel resolves as .relation ($rel wins)")
    func relationWinsOverFileRefShape() throws {
        // The $rel-array probe runs before the FileRef probe, so a $rel key on every
        // element makes it a relation regardless of co-present keys. Pins that order.
        let json = "[{\"path\":\"x.pdf\",\"original_name\":\"x.pdf\",\"$rel\":\"01TARGET\"}]"
        #expect(try decode(json) == .relation(["01TARGET"]))
    }

    // MARK: - Empty array

    @Test("an empty array decodes as .multiSelect([]) — the [String] probe catches it first")
    func emptyArrayIsMultiSelect() throws {
        // `[]` is caught by the `[String]` probe first, so an empty `.file([])` does not round-trip.
        #expect(try decode("[]") == .multiSelect([]))
    }
}
