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

    /// Parallel item-side seed (shared item_type parent FK).
    private func insertItem(id: String, title: String, index: PommoraIndex) throws {
        let ts = now()
        try index.dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO item_types (id, title, modified_at) VALUES (?, ?, ?)",
                arguments: ["it-test", "TestType", ts])
            try db.execute(
                sql: "INSERT INTO items (id, item_type_id, title, modified_at) VALUES (?, ?, ?, ?)",
                arguments: [id, "it-test", title, ts])
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

        let resolver = PommoraConnectionResolver(index: idx, kind: .page)
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

        let resolver = PommoraConnectionResolver(index: idx, kind: .page)
        #expect(resolver.resolve(displayName: "Ghost", range: NSRange(location: 0, length: 0)) == nil)
    }

    /// A title present TWICE (two pages, same title) is ambiguous → nil.
    @Test func duplicatePageTitleReturnsNil() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        try insertPage(id: ULID.generate(), title: "Dup", index: idx)
        try insertPage(id: ULID.generate(), title: "Dup", index: idx)

        let resolver = PommoraConnectionResolver(index: idx, kind: .page)
        #expect(resolver.resolve(displayName: "Dup", range: NSRange(location: 0, length: 0)) == nil)
    }

    /// Kind isolation: an item title resolves on the `.item` resolver, and a page
    /// with the same title does NOT make the `.item` resolver resolve.
    @Test func itemResolverIsKindIsolated() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let itemID = ULID.generate()
        try insertItem(id: itemID, title: "Beta", index: idx)
        // A page named "Gamma" must NOT be visible to the item resolver.
        try insertPage(id: ULID.generate(), title: "Gamma", index: idx)

        let itemResolver = PommoraConnectionResolver(index: idx, kind: .item)
        let hit = itemResolver.resolve(displayName: "Beta", range: NSRange(location: 0, length: 0))
        #expect(hit != nil)
        #expect(hit?.exists == true)
        #expect(hit?.id == itemID)

        // Page-only title is invisible to the item resolver.
        #expect(itemResolver.resolve(displayName: "Gamma", range: NSRange(location: 0, length: 0)) == nil)
    }
}
