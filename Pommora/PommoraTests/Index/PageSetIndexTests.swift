import Foundation
import GRDB
import Testing

@testable import Pommora

// MARK: - Suite

@Suite("PageSetIndex")
@MainActor
struct PageSetIndexTests {

    // MARK: - Fixture setup

    /// Builds a nexus with 1 PageType "Notes" + 1 PageSet "Inbox"
    /// + 1 PageSet "Drafts" inside it. One Page lives in the Set, one at the
    /// Collection root — the pair exercises both sides of `page_set_id`.
    private func setup() async throws -> (
        nexus: Nexus, idx: PommoraIndex,
        typeID: String, collectionID: String, setID: String,
        setPageID: String, rootPageID: String
    ) {
        let nexus = try TempNexus.make()

        let pageTypeManager = PageTypeManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageTypeProvider = { [weak pageTypeManager] in pageTypeManager?.types ?? [] }
        pageTypeManager.pageSetManager = setManager
        await pageTypeManager.loadAll()
        try await pageTypeManager.createPageType(name: "Notes", icon: nil)
        let pt = pageTypeManager.types.first!

        try await pageTypeManager.createPageCollection(name: "Inbox", inPageType: pt)
        let coll = pageTypeManager.pageCollections(in: pt).first!

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
                types: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_types") ?? -1,
                sets: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_sets") ?? -1,
                pages: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pages") ?? -1
            )
        }
        #expect(counts.types == 1)
        #expect(counts.sets == 2)  // depth-1 (Inbox) + depth-2 (Drafts)
        #expect(counts.pages == 2)

        // Depth-1 set row: parent_type_id set, parent_set_id null.
        let collRow = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM page_sets WHERE id = ?", arguments: [fx.collectionID])
        }
        #expect(collRow?["parent_type_id"] as String? == fx.typeID)
        #expect(collRow?["parent_set_id"] as String? == nil)
        #expect(collRow?["title"] as String? == "Inbox")

        // Depth-2 set row: parent_set_id set, parent_type_id null.
        let setRow = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM page_sets WHERE id = ?", arguments: [fx.setID])
        }
        #expect(setRow?["parent_set_id"] as String? == fx.collectionID)
        #expect(setRow?["parent_type_id"] as String? == nil)
        #expect(setRow?["title"] as String? == "Drafts")

        // The Set page carries type + set FKs; page_collection_id is null (set pages
        // are indexed purely by page_set_id from v15 onward).
        let setPageRow = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [fx.setPageID])
        }
        #expect(setPageRow?["page_type_id"] as String? == fx.typeID)
        #expect(setPageRow?["page_set_id"] as String? == fx.setID)

        // The root page (in the depth-1 set) also has page_set_id set.
        let rootPageRow = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [fx.rootPageID])
        }
        #expect(rootPageRow?["page_set_id"] as String? == fx.collectionID)
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
                arguments: [fx.collectionID]
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
        #expect(setContainer?.typeID == fx.typeID)
        #expect(setContainer?.typeTitle == "Notes")
        #expect(setContainer?.setID == fx.setID)
        #expect(setContainer?.setTitle == "Drafts")

        // The depth-1 Set page (root page of "Inbox"): page_set_id = collectionID.
        let rootContainer = try await query.entityContainer(id: fx.rootPageID, kind: .page)
        #expect(rootContainer?.setID == fx.collectionID)
        #expect(rootContainer?.setTitle == "Inbox")
    }

    // MARK: - IndexUpdater fallback chain

    @Test func upsertPageWithDanglingSetFallsBackToCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageType()
        try updater.upsertPageType(pt)
        let pc = Fixtures.pageCollection(parentID: pt.id)
        try updater.upsertPageCollection(pc)

        // The set FK dangles (never indexed) — the page must still land,
        // scoped to its Collection, without throwing.
        let meta = Fixtures.pageMeta()
        try updater.upsertPage(meta, pageTypeID: pt.id, pageCollectionID: pc.id, pageSetID: ULID.generate())

        let pageID = meta.id
        let row = try await idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [pageID])
        }
        #expect(row?["page_collection_id"] as String? == pc.id)
        #expect(row?["page_set_id"] as String? == nil)
    }

    @Test func upsertPageWithDanglingSetAndCollectionFallsBackToType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageType()
        try updater.upsertPageType(pt)

        // Both the set AND collection FKs dangle — the page still indexes
        // under its Vault alone.
        let meta = Fixtures.pageMeta()
        try updater.upsertPage(meta, pageTypeID: pt.id, pageCollectionID: ULID.generate(), pageSetID: ULID.generate())

        let pageID = meta.id
        let row = try await idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [pageID])
        }
        #expect(row?["page_type_id"] as String? == pt.id)
        #expect(row?["page_collection_id"] as String? == nil)
        #expect(row?["page_set_id"] as String? == nil)
    }

    @Test func upsertAndDeletePageSetRoundTrip() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageType()
        try updater.upsertPageType(pt)
        let pc = Fixtures.pageCollection(parentID: pt.id)
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
        #expect(row?["parent_type_id"] as String? == nil)
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
