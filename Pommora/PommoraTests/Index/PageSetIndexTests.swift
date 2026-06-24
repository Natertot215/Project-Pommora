import Foundation
import GRDB
import Testing

@testable import Pommora

// MARK: - Suite

@Suite("PageSetIndex")
@MainActor
struct PageSetIndexTests {

    // MARK: - Fixture setup

    /// Builds a nexus with 1 PageCollection "Notes" + 1 PageSet "Inbox"
    /// + 1 PageSet "Drafts" inside it. One Page lives in the Set, one at the
    /// Collection root — the pair exercises both sides of `page_set_id`.
    private func setup() async throws -> (
        nexus: Nexus, idx: PommoraIndex,
        collectionID: String, depthOneSetID: String, setID: String,
        setPageID: String, rootPageID: String
    ) {
        let nexus = try TempNexus.make()

        let collectionManager = PageCollectionManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageCollectionProvider = { [weak collectionManager] in collectionManager?.types ?? [] }
        collectionManager.pageSetManager = setManager
        await collectionManager.loadAll()
        try await collectionManager.createPageCollection(name: "Notes", icon: nil)
        let pt = collectionManager.types.first!

        try await collectionManager.createPageCollection(name: "Inbox", inPageCollection: pt)
        let coll = collectionManager.pageCollections(in: pt).first!

        // Lay down the Set folder + `_pageset.json` sidecar directly on disk
        // (the manager CRUD surface ships in a later task).
        let setFolder = coll.folderURL.appendingPathComponent("Drafts", isDirectory: true)
        try FileManager.default.createDirectory(at: setFolder, withIntermediateDirectories: true)
        let set = PageSet(
            id: ULID.generate(), parentID: coll.id, title: "Drafts",
            folderURL: setFolder, modifiedAt: Date()
        )
        try set.save(to: setFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))

        // One Page inside the Set, one at the Collection root.
        let now = Date()
        let setPageFM = PageFrontmatter(
            id: ULID.generate(), icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: now, modifiedAt: now
        )
        let rootPageFM = PageFrontmatter(
            id: ULID.generate(), icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: now, modifiedAt: now
        )
        try AtomicYAMLMarkdown.write(
            frontmatter: setPageFM, body: "",
            to: NexusPaths.pageFileURL(forTitle: "Set Page", in: setFolder))
        try AtomicYAMLMarkdown.write(
            frontmatter: rootPageFM, body: "",
            to: NexusPaths.pageFileURL(forTitle: "Root Page", in: coll.folderURL))

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        return (nexus, idx, pt.id, coll.id, set.id, setPageFM.id, rootPageFM.id)
    }

    // MARK: - IndexBuilder population

    @Test func populateIndexesPageSetsWithCorrectFKs() async throws {
        let fx = try await setup()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        // page_sets holds both depth-1 (collection) and depth-2 (set) rows.
        let counts = try await fx.idx.dbQueue.read { db in
            (
                collections: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_collections") ?? -1,
                sets: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_sets") ?? -1,
                pages: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pages") ?? -1
            )
        }
        #expect(counts.collections == 1)
        #expect(counts.sets == 2)  // depth-1 (Inbox) + depth-2 (Drafts)
        #expect(counts.pages == 2)

        // Depth-1 set row: parent_collection_id set, parent_set_id null.
        let collRow = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM page_sets WHERE id = ?", arguments: [fx.depthOneSetID])
        }
        #expect(collRow?["parent_collection_id"] as String? == fx.collectionID)
        #expect(collRow?["parent_set_id"] as String? == nil)
        #expect(collRow?["title"] as String? == "Inbox")

        // Depth-2 set row: parent_set_id set, parent_collection_id null.
        let setRow = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM page_sets WHERE id = ?", arguments: [fx.setID])
        }
        #expect(setRow?["parent_set_id"] as String? == fx.depthOneSetID)
        #expect(setRow?["parent_collection_id"] as String? == nil)
        #expect(setRow?["title"] as String? == "Drafts")

        // Every page carries page_collection_id (top-tier collection) + page_set_id (immediate set).
        let setPageRow = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [fx.setPageID])
        }
        #expect(setPageRow?["page_collection_id"] as String? == fx.collectionID)
        #expect(setPageRow?["page_set_id"] as String? == fx.setID)

        // The root page (in the depth-1 set) carries the collection id + depth-1 set id.
        let rootPageRow = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [fx.rootPageID])
        }
        #expect(rootPageRow?["page_collection_id"] as String? == fx.collectionID)
        #expect(rootPageRow?["page_set_id"] as String? == fx.depthOneSetID)
    }

    @Test func populateExcludesSetPagesFromCollectionRollup() async throws {
        let fx = try await setup()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        // Exactly one page is scoped to the depth-1 set (Inbox) directly —
        // the depth-2 Set page must not roll up into the depth-1 Set's scope.
        let rootScoped = try await fx.idx.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pages WHERE page_set_id = ?",
                arguments: [fx.depthOneSetID]
            ) ?? -1
        }
        #expect(rootScoped == 1)
    }

    // MARK: - entityContainer

    @Test func entityContainerResolvesSetFields() async throws {
        let fx = try await setup()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)
        let query = IndexQuery(fx.idx)

        // The depth-2 Set page: type resolved, set resolved via page_set_id.
        let setContainer = try await query.entityContainer(id: fx.setPageID, kind: .page)
        #expect(setContainer?.collectionID == fx.collectionID)
        #expect(setContainer?.collectionTitle == "Notes")
        #expect(setContainer?.setID == fx.setID)
        #expect(setContainer?.setTitle == "Drafts")

        // The depth-1 Set page (root page of "Inbox"): page_set_id = depthOneSetID.
        let rootContainer = try await query.entityContainer(id: fx.rootPageID, kind: .page)
        #expect(rootContainer?.setID == fx.depthOneSetID)
        #expect(rootContainer?.setTitle == "Inbox")
    }

    // MARK: - IndexUpdater fallback chain

    @Test func upsertPageWithDanglingSetFallsBackToCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageCollection()
        try updater.upsertPageCollection(pt)
        let pc = Fixtures.pageSetAsCollection(parentID: pt.id)
        try updater.upsertPageCollection(pc)

        // The set FK dangles (never indexed) — the page must still land,
        // scoped to its Collection, without throwing.
        let meta = Fixtures.pageMeta()
        try updater.upsertPage(meta, pageCollectionID: pt.id, pageSetID: ULID.generate())

        let pageID = meta.id
        let row = try await idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [pageID])
        }
        #expect(row?["page_collection_id"] as String? == pt.id)
        #expect(row?["page_set_id"] as String? == nil)
    }

    @Test func upsertPageWithDanglingSetAndCollectionFallsBackToType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageCollection()
        try updater.upsertPageCollection(pt)

        // The set FK dangles — the page still indexes under its Collection (page_collection_id=pt.id,
        // page_set_id=nil) with the dangling set FK NULLed out.
        let meta = Fixtures.pageMeta()
        try updater.upsertPage(meta, pageCollectionID: pt.id, pageSetID: ULID.generate())

        let pageID = meta.id
        let row = try await idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [pageID])
        }
        #expect(row?["page_collection_id"] as String? == pt.id)
        #expect(row?["page_set_id"] as String? == nil)
    }

    @Test func upsertAndDeletePageSetRoundTrip() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageCollection()
        try updater.upsertPageCollection(pt)
        let pc = Fixtures.pageSetAsCollection(parentID: pt.id)
        try updater.upsertPageCollection(pc)

        let set = PageSet(
            id: ULID.generate(), parentID: pc.id, title: "Drafts",
            folderURL: URL(fileURLWithPath: "/tmp/dummy-\(UUID().uuidString)"),
            modifiedAt: Date()
        )
        try updater.upsertPageSet(set)

        let setID = set.id
        let row = try await idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM page_sets WHERE id = ?", arguments: [setID])
        }
        #expect(row?["parent_set_id"] as String? == pc.id)
        #expect(row?["parent_collection_id"] as String? == nil)
        #expect(row?["title"] as String? == "Drafts")

        // Re-upsert (rename) updates in place — no cascade fires on the member FK.
        var renamed = set
        renamed.title = "Outbox"
        renamed.modifiedAt = Date()
        try updater.upsertPageSet(renamed)
        let renamedID = set.id
        let title = try await idx.dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT title FROM page_sets WHERE id = ?", arguments: [renamedID])
        }
        #expect(title == "Outbox")

        try updater.deletePageSet(id: setID)
        let count = try await idx.dbQueue.read { db in
            // pc (depth-1) still exists; only the depth-2 set was deleted.
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_sets WHERE id = ?", arguments: [setID]) ?? -1
        }
        #expect(count == 0)
    }
}
