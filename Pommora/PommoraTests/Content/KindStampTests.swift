import Foundation
import Testing

@testable import Pommora

/// Task 2 — `KindStamp` + the `Class` Codable property on `PageFrontmatter`.
///
/// `KindStamp` is the reserved, UI-hidden on-disk stamp distinguishing the two
/// forms of one entity-type, serialized as the frontmatter key `Class`. On
/// `PageFrontmatter` it encodes UNCONDITIONALLY (every typed Page save stamps
/// `Class: page`) and decodes leniently — a missing OR unknown `Class:` value
/// defaults to `.page` rather than throwing, so a foreign file (`Class: widget`)
/// never bricks a Page load.
@Suite("KindStamp")
struct KindStampTests {

    /// JSONEncoder + JSONDecoder with ISO-8601 dates — same shape used by the
    /// sibling `PageFrontmatterTests`. The actual on-disk path is YAML via Yams,
    /// but Codable semantics are identical and JSON is faster to round-trip.
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

    private static func makeFM(id: String, kind: KindStamp = .page) -> PageFrontmatter {
        PageFrontmatter(
            id: id, icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(timeIntervalSince1970: 0),
            kind: kind
        )
    }

    // MARK: - 1. Raw values

    @Test("KindStamp raw values map item/page and reject unknown")
    func rawValues() {
        #expect(KindStamp(rawValue: "item") == .item)
        #expect(KindStamp(rawValue: "page") == .page)
        #expect(KindStamp(rawValue: "widget") == nil)
    }

    // MARK: - 2. Typed Page save emits `Class: page` to disk

    @Test("a typed Page write emits Class: page in the on-disk frontmatter")
    func typedPageSaveEmitsClassPage() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Stamped.md")

        // kind defaults to .page; saved through the real PageFile/YAML pipeline.
        try PageFile(frontmatter: Self.makeFM(id: "01HSTAMP"), body: "# Body\n").save(to: url)

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("Class: page"))
    }

    // MARK: - 3. Decode WITHOUT a Class key defaults to .page

    @Test("decode without a Class key defaults kind to .page")
    func decodeMissingClassDefaultsToPage() throws {
        let json = """
            {
              "id": "01HABC",
              "tier1": [], "tier2": [], "tier3": [],
              "properties": {},
              "created_at": "2026-05-01T00:00:00Z"
            }
            """.data(using: .utf8)!
        let fm = try Self.decoder().decode(PageFrontmatter.self, from: json)
        #expect(fm.kind == .page)
    }

    // MARK: - 4. Decode an UNKNOWN Class value does NOT throw and defaults

    @Test("decode of an unknown Class value does not throw and defaults to .page")
    func decodeUnknownClassDefaultsAndDoesNotThrow() throws {
        // A foreign file with `Class: widget` — a naive `decodeIfPresent(KindStamp.self)`
        // would THROW here; the lenient string-then-map path must default instead.
        let json = """
            {
              "id": "01HFOREIGN",
              "Class": "widget",
              "tier1": [], "tier2": [], "tier3": [],
              "properties": {},
              "created_at": "2026-05-01T00:00:00Z"
            }
            """.data(using: .utf8)!
        let fm = try Self.decoder().decode(PageFrontmatter.self, from: json)
        #expect(fm.kind == .page)
    }

    // MARK: - 5. Round-trip honors the stored value

    @Test("kind round-trips: .page stays .page, an explicit .item stays .item")
    func kindRoundTrips() throws {
        let pageFM = Self.makeFM(id: "01HPAGE")
        let pageData = try Self.encoder().encode(pageFM)
        let pageStr = String(data: pageData, encoding: .utf8)!
        #expect(pageStr.contains(#""Class":"page""#))
        let decodedPage = try Self.decoder().decode(PageFrontmatter.self, from: pageData)
        #expect(decodedPage.kind == .page)

        // An explicitly `.item`-stamped frontmatter must round-trip to `.item` —
        // proving the value is honored, not just defaulted.
        let itemFM = Self.makeFM(id: "01HITEM", kind: .item)
        let itemData = try Self.encoder().encode(itemFM)
        let itemStr = String(data: itemData, encoding: .utf8)!
        #expect(itemStr.contains(#""Class":"item""#))
        let decodedItem = try Self.decoder().decode(PageFrontmatter.self, from: itemData)
        #expect(decodedItem.kind == .item)
    }
}
