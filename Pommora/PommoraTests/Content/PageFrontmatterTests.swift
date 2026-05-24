import Foundation
import Testing
@testable import Pommora

@Suite("PageFrontmatter") struct PageFrontmatterTests {

    /// JSONEncoder + JSONDecoder with ISO-8601 dates — same shape used by AtomicJSON
    /// (the actual on-disk path for Pages is YAML via Yams, but the Codable semantics
    /// are identical and JSON is faster to round-trip in tests).
    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    @Test func legacyDecodeWithoutModifiedAtYieldsNil() throws {
        let json = """
        {
          "id": "01HABC",
          "tier1": [], "tier2": [], "tier3": [],
          "properties": {},
          "created_at": "2026-05-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let fm = try Self.decoder().decode(PageFrontmatter.self, from: json)
        #expect(fm.id == "01HABC")
        #expect(fm.modifiedAt == nil)  // signals "backfill from file mtime"
    }

    @Test func modifiedAtRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1_716_480_000)
        let fm = PageFrontmatter(
            id: "01HABC", icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: now,
            modifiedAt: now
        )
        let data = try Self.encoder().encode(fm)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""modified_at""#))
        let decoded = try Self.decoder().decode(PageFrontmatter.self, from: data)
        #expect(decoded.modifiedAt == now)
    }

    @Test func modifiedAtNilOmittedFromEncoding() throws {
        let fm = PageFrontmatter(
            id: "01HABC", icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let data = try Self.encoder().encode(fm)
        let s = String(data: data, encoding: .utf8)!
        #expect(!s.contains("modified_at"))
    }
}
