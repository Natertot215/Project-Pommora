import Foundation
import GRDB
import Testing

@testable import Pommora

// MARK: - Suite

@Suite("PageSetIndex")
@MainActor
struct PageSetIndexTests {

    // MARK: - Fixture setup

    /// Builds a nexus with 1 PageType "Notes" + 1 PageCollection "Inbox"
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
            id: ULID.generate(), collectionID: coll.id, title: "Drafts",
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

        // Every container table is populated.
        let counts = try await fx.idx.dbQueue.read { db in
            (
                types: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_types") ?? -1,
                collections: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_collections") ?? -1,
                sets: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_sets") ?? -1,
                pages: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pages") ?? -1
            )
        }
        #expect(counts.types == 1)
        #expect(counts.collections == 1)
        #expect(counts.sets == 1)
        #expect(counts.pages == 2)

        // page_sets row carries the parent Collection FK + folder-derived title.
        let setRow = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM page_sets WHERE id = ?", arguments: [fx.setID])
        }
        #expect(setRow?["page_collection_id"] as String? == fx.collectionID)
        #expect(setRow?["title"] as String? == "Drafts")

        // The Set page carries all three container FKs; the root page has no set.
        let setPageRow = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [fx.setPageID])
        }
        #expect(setPageRow?["page_type_id"] as String? == fx.typeID)
        #expect(setPageRow?["page_collection_id"] as String? == fx.collectionID)
        #expect(setPageRow?["page_set_id"] as String? == fx.setID)

        let rootPageRow = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [fx.rootPageID])
        }
        #expect(rootPageRow?["page_set_id"] as String? == nil)
        #expect(rootPageRow?["page_collection_id"] as String? == fx.collectionID)
    }

    @Test func populateExcludesSetPagesFromCollectionRollup() async throws {
        let fx = try await setup()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        // Exactly one page rolls up at the Collection root — the Set page must
        // not double-count into the Collection's own (set-less) scope.
        let rootScoped = try await fx.idx.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pages WHERE page_collection_id = ? AND page_set_id IS NULL",
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

        let setContainer = try await query.entityContainer(id: fx.setPageID, kind: .page)
        #expect(setContainer?.typeID == fx.typeID)
        #expect(setContainer?.typeTitle == "Notes")
        #expect(setContainer?.collectionID == fx.collectionID)
        #expect(setContainer?.collectionTitle == "Inbox")
        #expect(setContainer?.setID == fx.setID)
        #expect(setContainer?.setTitle == "Drafts")

        // A Collection-root page resolves with nil set fields.
        let rootContainer = try await query.entityContainer(id: fx.rootPageID, kind: .page)
        #expect(rootContainer?.collectionID == fx.collectionID)
        #expect(rootContainer?.setID == nil)
        #expect(rootContainer?.setTitle == nil)
    }

    // MARK: - IndexUpdater fallback chain

    @Test func upsertPageWithDanglingSetFallsBackToCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(idx)

        let pt = Fixtures.pageType()
        try updater.upsertPageType(pt)
        let pc = Fixtures.pageCollection(typeID: pt.id)
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
        let pc = Fixtures.pageCollection(typeID: pt.id)
        try updater.upsertPageCollection(pc)

        let set = PageSet(
            id: ULID.generate(), collectionID: pc.id, title: "Drafts",
            folderURL: URL(fileURLWithPath: "/tmp/dummy-\(UUID().uuidString)"),
            modifiedAt: Date()
        )
        try updater.upsertPageSet(set)

        let setID = set.id
        let row = try await idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM page_sets WHERE id = ?", arguments: [setID])
        }
        #expect(row?["page_collection_id"] as String? == pc.id)
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

        try updater.deletePageSet(id: set.id)
        let count = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_sets") ?? -1
        }
        #expect(count == 0)
    }
}
