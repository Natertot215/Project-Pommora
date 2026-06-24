import Foundation
import GRDB
import MarkdownPM
import Testing

@testable import Pommora

/// Pins `IndexQuery.titleCandidates` ranking: exact title first → shortest title
/// → A–Z. These orderings would FAIL under the old `ORDER BY title` (pure
/// alphabetical) — see the "Note"-prefix case below.
@Suite("ConnectionRankingTests")
@MainActor
struct ConnectionRankingTests {

    private func now() -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.string(from: Date())
    }

    private func insertPage(id: String, title: String, index: PommoraIndex) throws {
        let ts = now()
        try index.dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO page_collections (id, title, modified_at) VALUES (?, ?, ?)",
                arguments: ["pc-test", "TestVault", ts])
            try db.execute(
                sql: "INSERT INTO pages (id, page_collection_id, title, modified_at) VALUES (?, ?, ?, ?)",
                arguments: [id, "pc-test", title, ts])
        }
    }

    private func titles(_ refs: [EntityRef]) -> [String] { refs.map(\.title) }

    /// Exact match floats above the alphabetically-earlier longer title.
    /// Old `ORDER BY title` gives ["Note", "Note Archive", "Notes"] (alphabetical) —
    /// the new ranking gives ["Note", "Notes", "Note Archive"] (exact, then length).
    @Test func exactThenLengthBeatsAlphabetical() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        try insertPage(id: ULID.generate(), title: "Notes", index: index)
        try insertPage(id: ULID.generate(), title: "Note Archive", index: index)
        try insertPage(id: ULID.generate(), title: "Note", index: index)
        try insertPage(id: ULID.generate(), title: "Meeting", index: index)  // non-matching

        let refs = try await IndexQuery(index).titleCandidates(matching: "Note")
        #expect(titles(refs) == ["Note", "Notes", "Note Archive"])
    }

    /// No exact match → shortest first, then A–Z.
    @Test func noExactSortsByLengthThenAlpha() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        try insertPage(id: ULID.generate(), title: "Notes", index: index)
        try insertPage(id: ULID.generate(), title: "Note Archive", index: index)
        try insertPage(id: ULID.generate(), title: "Note", index: index)
        try insertPage(id: ULID.generate(), title: "Meeting", index: index)  // non-matching

        let refs = try await IndexQuery(index).titleCandidates(matching: "no")
        #expect(titles(refs) == ["Note", "Notes", "Note Archive"])
    }

    /// Exact beats equal-length alphabetical: "Car" (exact) tops "Care"/"Cart"
    /// even though "Car" is shortest anyway; the equal-length pair then sorts A–Z.
    @Test func exactFirstThenEqualLengthAlpha() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        try insertPage(id: ULID.generate(), title: "Cart", index: index)
        try insertPage(id: ULID.generate(), title: "Care", index: index)
        try insertPage(id: ULID.generate(), title: "Car", index: index)

        let refs = try await IndexQuery(index).titleCandidates(matching: "car")
        #expect(titles(refs) == ["Car", "Care", "Cart"])
    }
}
