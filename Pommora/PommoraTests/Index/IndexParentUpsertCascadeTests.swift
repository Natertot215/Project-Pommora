import Foundation
import GRDB
import Testing

@testable import Pommora

// MARK: - Suite

/// Regression suite for the `INSERT OR REPLACE` cascade-wipe bug.
///
/// `INSERT OR REPLACE` on an existing primary key DELETEs the existing row
/// (firing every `ON DELETE CASCADE` / `ON DELETE SET NULL` child FK) then
/// re-inserts. The parent tables (`page_collections` / `page_sets`) are
/// cascade parents of pages, so re-upserting an already-present parent — which
/// `loadAll` does on every launch as a defensive index sync (quirk #14) —
/// cascade-wiped (or NULLed) every child page. The fix converts the parent
/// upserts to a non-deleting `INSERT ... ON CONFLICT(id) DO UPDATE`. These
/// tests prove children survive a re-upsert of their parent.
@Suite("IndexParentUpsertCascade")
@MainActor
struct IndexParentUpsertCascadeTests {

    // MARK: - Helpers

    private func count(_ table: String, in index: PommoraIndex) throws -> Int {
        try index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
        }
    }

    /// The `page_set_id` currently stored for `pageID` (nil if the column is NULL
    /// or the row is gone). Wrapped in a non-isolated helper so the synchronous
    /// `dbQueue.read` overload resolves cleanly inside the @MainActor suite.
    private func pageSetID(of pageID: String, in index: PommoraIndex) throws -> String? {
        try index.dbQueue.read { db in
            let row = try Row.fetchOne(
                db, sql: "SELECT page_set_id FROM pages WHERE id = ?", arguments: [pageID])
            return row?["page_set_id"] as String?
        }
    }

    // MARK: - Tests

    @Test func reUpsertPageCollectionPreservesChildPages() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageCollection()
        try updater.upsertPageCollection(pt)
        try updater.upsertPage(Fixtures.pageMeta(title: "Page One"), pageCollectionID: pt.id)
        try updater.upsertPage(Fixtures.pageMeta(title: "Page Two"), pageCollectionID: pt.id)

        let pagesBefore = try count("pages", in: idx)
        #expect(pagesBefore == 2)

        // Re-upsert the SAME page collection — simulating loadAll's defensive re-sync.
        try updater.upsertPageCollection(pt)

        let pagesAfter = try count("pages", in: idx)
        let collectionsAfter = try count("page_collections", in: idx)
        #expect(pagesAfter == 2, "re-upserting the parent page collection must not cascade-wipe child pages")
        #expect(collectionsAfter == 1, "re-upsert must update in place, not duplicate")
    }

    @Test func reUpsertPageSetPreservesChildLinkage() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageCollection()
        try updater.upsertPageCollection(pt)
        let pc = Fixtures.pageSetCollection(parentID: pt.id)
        try updater.upsertPageCollection(pc)

        let pageMeta = Fixtures.pageMeta(title: "Filed Page")
        try updater.upsertPage(pageMeta, pageCollectionID: pt.id, pageSetID: pc.id)

        // Hoist ids out before the read helpers (quirk #5: @MainActor local
        // captured in a Sendable closure is a strict-concurrency error).
        let pageID = pageMeta.id
        let setID = pc.id

        // Sanity: the page is filed under the set.
        let before = try pageSetID(of: pageID, in: idx)
        #expect(before == setID)

        // Re-upsert the SAME depth-1 set — `ON DELETE SET NULL` would NULL the
        // child's page_set_id under INSERT OR REPLACE.
        try updater.upsertPageCollection(pc)

        let pagesAfter = try count("pages", in: idx)
        let after = try pageSetID(of: pageID, in: idx)
        #expect(pagesAfter == 1, "re-upserting the set must not delete the child page")
        #expect(
            after == setID,
            "re-upserting the set must not NULL the child page's page_set_id"
        )
    }
}
