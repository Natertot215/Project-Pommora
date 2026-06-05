import Foundation
import GRDB
import Testing

@testable import Pommora

@MainActor
@Suite("ContextDisplayResolverTests")
struct ContextDisplayResolverTests {

    // Mirrors `ResolveEntitiesTests.setupIndex`: real on-disk temp DB via
    // `PommoraIndex.open(at:)` (there is no `PommoraIndex.inMemory()` helper).
    private func setupIndex() async throws -> (URL, PommoraIndex) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextDisplayResolverTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (idx, _) = try PommoraIndex.open(at: dir)
        return (dir, idx)
    }

    @Test("warm then resolve returns icon+title; unknown IDs stay nil")
    func warmsAndResolves() async throws {
        let (dir, idx) = try await setupIndex()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Seed a page P1 ("Doc", icon "star"). page_type_id is an enforced FK and
        // modified_at is NOT NULL, so seed the parent page_type + modified_at first.
        try await idx.dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO page_types (id, title, modified_at) VALUES (?,?,?)",
                arguments: ["PT1", "Notes", "2026-05-29T00:00:00Z"])
            try db.execute(
                sql: "INSERT INTO pages (id, title, icon, page_type_id, modified_at) VALUES (?,?,?,?,?)",
                arguments: ["P1", "Doc", "star", "PT1", "2026-05-29T00:00:00Z"])
        }

        let resolver = ContextDisplayResolver(index: { idx })

        // Not warmed yet → synchronous read is nil.
        #expect(resolver.resolve("P1") == nil)
        #expect(resolver.entity("P1") == nil)

        await resolver.warm(["P1", "P2"])

        #expect(resolver.resolve("P1")?.title == "Doc")
        #expect(resolver.resolve("P1")?.icon == "star")
        #expect(resolver.resolve("P2") == nil)  // no such entity

        // entity(_:) exposes the full cached EntityRef.
        #expect(resolver.entity("P1")?.kind == .page)
        #expect(resolver.entity("P1")?.icon == "star")
        #expect(resolver.entity("P2") == nil)

        // invalidate() drops the cache → reads go back to nil.
        resolver.invalidate()
        #expect(resolver.resolve("P1") == nil)
    }
}
