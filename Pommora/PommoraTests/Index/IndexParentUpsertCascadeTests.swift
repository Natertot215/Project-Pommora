import Foundation
import GRDB
import Testing

@testable import Pommora

// MARK: - Suite

/// Regression suite for the `INSERT OR REPLACE` cascade-wipe bug.
///
/// `INSERT OR REPLACE` on an existing primary key DELETEs the existing row
/// (firing every `ON DELETE CASCADE` / `ON DELETE SET NULL` child FK) then
/// re-inserts. The four parent tables (`page_types` / `item_types` /
/// `page_collections` / `item_collections`) are cascade parents of pages/items,
/// so re-upserting an already-present parent — which `loadAll` does on every
/// launch as a defensive index sync (quirk #14) — cascade-wiped (or NULLed)
/// every child page/item. The fix converts the parent upserts to a non-deleting
/// `INSERT ... ON CONFLICT(id) DO UPDATE`. These tests prove children survive a
/// re-upsert of their parent.
@Suite("IndexParentUpsertCascade")
@MainActor
struct IndexParentUpsertCascadeTests {

    // MARK: - Helpers

    private func makeIndex(at nexus: Nexus) throws -> PommoraIndex {
        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        return idx
    }

    private func count(_ table: String, in index: PommoraIndex) throws -> Int {
        try index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
        }
    }

    /// The `page_collection_id` currently stored for `pageID` (nil if the column is NULL
    /// or the row is gone). Wrapped in a non-isolated helper so the synchronous
    /// `dbQueue.read` overload resolves cleanly inside the @MainActor suite.
    private func pageCollectionID(of pageID: String, in index: PommoraIndex) throws -> String? {
        try index.dbQueue.read { db in
            let row = try Row.fetchOne(
                db, sql: "SELECT page_collection_id FROM pages WHERE id = ?", arguments: [pageID])
            return row?["page_collection_id"] as String?
        }
    }

    private func makePageType(title: String = "Notes") -> PageType {
        PageType(id: ULID.generate(), title: title, icon: nil, properties: [], views: [], modifiedAt: Date())
    }

    private func makeItemType(title: String = "Tasks") -> ItemType {
        ItemType(id: ULID.generate(), title: title, icon: nil, properties: [], views: [], modifiedAt: Date())
    }

    private func makePageCollection(typeID: String, title: String = "Archive") -> PageCollection {
        let folderURL = URL(fileURLWithPath: "/tmp/dummy-\(UUID().uuidString)")
        return PageCollection(
            id: ULID.generate(), typeID: typeID, title: title, folderURL: folderURL, modifiedAt: Date()
        )
    }

    private func makePageMeta(id: String = ULID.generate(), title: String) -> PageMeta {
        let url = URL(fileURLWithPath: "/tmp/\(id).md")
        let frontmatter = PageFrontmatter(
            id: id, icon: nil, tier1: [], tier2: [], tier3: [], properties: [:], createdAt: Date()
        )
        return PageMeta(id: id, title: title, url: url, frontmatter: frontmatter)
    }

    private func makeItem(title: String) -> Item {
        let now = Date()
        return Item(
            id: ULID.generate(), title: title, icon: nil, description: "",
            tier1: [], tier2: [], tier3: [], properties: [:],
            createdAt: now, modifiedAt: now
        )
    }

    // MARK: - Tests

    @Test func reUpsertPageTypePreservesChildPages() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = makePageType()
        try updater.upsertPageType(pt)
        try updater.upsertPage(makePageMeta(title: "Page One"), pageTypeID: pt.id, pageCollectionID: nil)
        try updater.upsertPage(makePageMeta(title: "Page Two"), pageTypeID: pt.id, pageCollectionID: nil)

        let pagesBefore = try count("pages", in: idx)
        #expect(pagesBefore == 2)

        // Re-upsert the SAME page type — simulating loadAll's defensive re-sync.
        try updater.upsertPageType(pt)

        let pagesAfter = try count("pages", in: idx)
        let typesAfter = try count("page_types", in: idx)
        #expect(pagesAfter == 2, "re-upserting the parent page type must not cascade-wipe child pages")
        #expect(typesAfter == 1, "re-upsert must update in place, not duplicate")
    }

    @Test func reUpsertItemTypePreservesChildItems() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let it = makeItemType()
        try updater.upsertItemType(it)
        try updater.upsertItem(makeItem(title: "Item One"), itemTypeID: it.id, itemCollectionID: nil)
        try updater.upsertItem(makeItem(title: "Item Two"), itemTypeID: it.id, itemCollectionID: nil)

        let itemsBefore = try count("items", in: idx)
        #expect(itemsBefore == 2)

        // Re-upsert the SAME item type — simulating loadAll's defensive re-sync.
        try updater.upsertItemType(it)

        let itemsAfter = try count("items", in: idx)
        let typesAfter = try count("item_types", in: idx)
        #expect(itemsAfter == 2, "re-upserting the parent item type must not cascade-wipe child items")
        #expect(typesAfter == 1, "re-upsert must update in place, not duplicate")
    }

    @Test func reUpsertPageCollectionPreservesChildLinkage() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = makePageType()
        try updater.upsertPageType(pt)
        let pc = makePageCollection(typeID: pt.id)
        try updater.upsertPageCollection(pc)

        let pageMeta = makePageMeta(title: "Filed Page")
        try updater.upsertPage(pageMeta, pageTypeID: pt.id, pageCollectionID: pc.id)

        // Hoist ids out before the read helpers (quirk #5: @MainActor local
        // captured in a Sendable closure is a strict-concurrency error).
        let pageID = pageMeta.id
        let collectionID = pc.id

        // Sanity: the page is filed under the collection.
        let before = try pageCollectionID(of: pageID, in: idx)
        #expect(before == collectionID)

        // Re-upsert the SAME page collection — `ON DELETE SET NULL` would NULL the
        // child's page_collection_id under INSERT OR REPLACE.
        try updater.upsertPageCollection(pc)

        let pagesAfter = try count("pages", in: idx)
        let after = try pageCollectionID(of: pageID, in: idx)
        #expect(pagesAfter == 1, "re-upserting the collection must not delete the child page")
        #expect(
            after == collectionID,
            "re-upserting the collection must not NULL the child page's page_collection_id"
        )
    }
}
