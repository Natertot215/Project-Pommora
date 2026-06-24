import Foundation
import GRDB
import Testing

@testable import Pommora

@Suite("ResolveEntitiesTests")
@MainActor
struct ResolveEntitiesTests {

    // Mirrors `IndexQueryTests.setupIndex`: real on-disk temp DB via
    // `PommoraIndex.open(at:)` (there is no `PommoraIndex.inMemory()` helper).
    private func setupIndex() async throws -> (URL, PommoraIndex) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResolveEntitiesTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (idx, _) = try PommoraIndex.open(at: dir)
        return (dir, idx)
    }

    @Test("resolveEntities returns icon + title for a page ID and a context ID")
    func resolvesAcrossTables() async throws {
        let (dir, idx) = try await setupIndex()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await idx.dbQueue.write { db in
            try db.execute(sql: "INSERT INTO page_collections (id, title, modified_at) VALUES (?,?,?)",
                           arguments: ["PT1", "Notes", "2026-05-29T00:00:00Z"])
            try db.execute(sql: "INSERT INTO pages (id, title, icon, page_collection_id, modified_at) VALUES (?,?,?,?,?)",
                           arguments: ["P1", "My Page", "doc.text", "PT1", "2026-05-29T00:00:00Z"])
            try db.execute(sql: "INSERT INTO contexts (id, title, icon, tier) VALUES (?,?,?,?)",
                           arguments: ["S1", "Work", "square.stack.3d.up", 1])
        }

        let out = try await IndexQuery(idx).resolveEntities(ids: ["P1", "S1", "missing"])
        #expect(out["P1"]?.title == "My Page")
        #expect(out["P1"]?.icon == "doc.text")
        #expect(out["P1"]?.kind == .page)
        #expect(out["S1"]?.kind == .area)
        #expect(out["S1"]?.icon == "square.stack.3d.up")
        #expect(out["missing"] == nil)
    }
}
