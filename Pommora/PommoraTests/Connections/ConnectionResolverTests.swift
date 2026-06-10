import Foundation
import GRDB
import MarkdownPM
import Testing

@testable import Pommora

@Suite("ConnectionResolverTests")
@MainActor
struct ConnectionResolverTests {

    // MARK: - Helpers

    private func makeIndex(at nexus: Nexus) throws -> PommoraIndex {
        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        return idx
    }

    private func now() -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.string(from: Date())
    }

    /// Insert a pages row (with its required page_type parent). `pages.page_type_id`
    /// is NOT NULL + FK, so seed a shared parent first (INSERT OR IGNORE — idempotent).
    private func insertPage(id: String, title: String, index: PommoraIndex) throws {
        let ts = now()
        try index.dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO page_types (id, title, modified_at) VALUES (?, ?, ?)",
                arguments: ["pt-test", "TestVault", ts])
            try db.execute(
                sql: "INSERT INTO pages (id, page_type_id, title, modified_at) VALUES (?, ?, ?, ?)",
                arguments: [id, "pt-test", title, ts])
        }
    }

    // MARK: - Tests

    /// A page title present exactly once resolves to a live link.
    @Test func uniquePageTitleResolves() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let id = ULID.generate()
        try insertPage(id: id, title: "Alpha", index: idx)

        let resolver = PommoraConnectionResolver(index: idx)
        let resolution = resolver.resolve(displayName: "Alpha", range: NSRange(location: 0, length: 0))
        #expect(resolution != nil)
        #expect(resolution?.exists == true)
        #expect(resolution?.id == id)
    }

    /// A missing title resolves to nil (renders unresolved).
    @Test func missingPageTitleReturnsNil() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)

        let resolver = PommoraConnectionResolver(index: idx)
        #expect(resolver.resolve(displayName: "Ghost", range: NSRange(location: 0, length: 0)) == nil)
    }

    /// A title present TWICE (two pages, same title) is ambiguous → nil.
    @Test func duplicatePageTitleReturnsNil() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        try insertPage(id: ULID.generate(), title: "Dup", index: idx)
        try insertPage(id: ULID.generate(), title: "Dup", index: idx)

        let resolver = PommoraConnectionResolver(index: idx)
        #expect(resolver.resolve(displayName: "Dup", range: NSRange(location: 0, length: 0)) == nil)
    }

    // MARK: - resolvePageByIDOrTitle

    /// A direct page ID returns that same ID immediately — fast path.
    @Test func resolveByDirectID() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let id = ULID.generate()
        try insertPage(id: id, title: "Bravo", index: idx)

        #expect(IndexQuery(idx).resolvePageByIDOrTitle(id) == id)
    }

    /// A display title (original case) falls through to title-match.
    @Test func resolveByDisplayTitle() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let id = ULID.generate()
        try insertPage(id: id, title: "Project Notes", index: idx)

        #expect(IndexQuery(idx).resolvePageByIDOrTitle("Project Notes") == id)
    }

    /// Title matching is case-insensitive (wikilinks are typed free-form).
    @Test func resolveByTitleCaseInsensitive() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let id = ULID.generate()
        try insertPage(id: id, title: "Meeting Notes", index: idx)

        #expect(IndexQuery(idx).resolvePageByIDOrTitle("meeting notes") == id)
        #expect(IndexQuery(idx).resolvePageByIDOrTitle("MEETING NOTES") == id)
    }

    /// An unknown string that matches neither an ID nor a title returns nil.
    @Test func resolveUnknownReturnsNil() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)

        #expect(IndexQuery(idx).resolvePageByIDOrTitle("phantom-id-000") == nil)
    }

    /// Two pages sharing a title are ambiguous: title path returns nil.
    /// (Direct-ID path is unambiguous and still works for either.)
    @Test func resolveAmbiguousTitleReturnsNil() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let id1 = ULID.generate()
        let id2 = ULID.generate()
        try insertPage(id: id1, title: "Dup", index: idx)
        try insertPage(id: id2, title: "Dup", index: idx)

        #expect(IndexQuery(idx).resolvePageByIDOrTitle("Dup") == nil)
        // Direct ID bypasses the ambiguity guard.
        #expect(IndexQuery(idx).resolvePageByIDOrTitle(id1) == id1)
        #expect(IndexQuery(idx).resolvePageByIDOrTitle(id2) == id2)
    }
}
