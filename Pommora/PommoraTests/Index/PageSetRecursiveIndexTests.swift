import Foundation
import GRDB
import Testing

@testable import Pommora

/// TDD tests for task 1.8 — recursive page_sets index (v15).
///
/// - 4-deep set fixture proves every row has exactly one of
///   `parent_type_id`/`parent_set_id` set, and a depth-3 page indexes
///   with the right `page_set_id`.
/// - `.pageSet(id)` query returns that Set's direct pages.
@Suite("PageSetRecursiveIndex")
@MainActor
struct PageSetRecursiveIndexTests {

    // MARK: - 4-deep fixture

    /// Builds:
    ///   Notes (PageCollection)
    ///   └── L1 (_pagecollection.json)        depth-1
    ///       └── L2 (_pageset.json)           depth-2
    ///           └── L3 (_pageset.json)       depth-3
    ///               └── L4 (_pageset.json)   depth-4
    ///                   └── Deep Page.md
    ///               └── L3 Page.md
    private func setupFourDeep() async throws -> (
        nexus: Nexus, idx: PommoraIndex,
        typeID: String, l1ID: String, l2ID: String, l3ID: String, l4ID: String,
        l3PageID: String
    ) {
        let nexus = try TempNexus.make()

        let collectionManager = PageCollectionManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageTypeProvider = { [weak collectionManager] in collectionManager?.types ?? [] }
        collectionManager.pageSetManager = setManager
        await collectionManager.loadAll()
        try await collectionManager.createPageCollection(name: "Notes", icon: nil)
        let pt = collectionManager.types.first!

        // L1: depth-1 set created as a collection (uses _pagecollection.json sidecar)
        try await collectionManager.createPageCollection(name: "L1", inPageCollection: pt)
        let l1 = collectionManager.pageCollections(in: pt).first!

        func makeSet(name: String, parentID: String, inFolder: URL) throws -> PageSet {
            let folder = inFolder.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let set = PageSet(id: ULID.generate(), parentID: parentID, title: name, folderURL: folder, modifiedAt: Date())
            try set.save(to: folder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
            return set
        }

        let l2 = try makeSet(name: "L2", parentID: l1.id, inFolder: l1.folderURL)
        let l3 = try makeSet(name: "L3", parentID: l2.id, inFolder: l2.folderURL)
        let l4 = try makeSet(name: "L4", parentID: l3.id, inFolder: l3.folderURL)

        // One page at depth-3 (inside L3), one at depth-4 (inside L4)
        let now = Date()
        let l3PageFM = PageFrontmatter(id: ULID.generate(), icon: nil, tier1: [], tier2: [], tier3: [], properties: [:], createdAt: now, modifiedAt: now)
        try AtomicYAMLMarkdown.write(frontmatter: l3PageFM, body: "", to: NexusPaths.pageFileURL(forTitle: "L3 Page", in: l3.folderURL))

        let l4PageFM = PageFrontmatter(id: ULID.generate(), icon: nil, tier1: [], tier2: [], tier3: [], properties: [:], createdAt: now, modifiedAt: now)
        try AtomicYAMLMarkdown.write(frontmatter: l4PageFM, body: "", to: NexusPaths.pageFileURL(forTitle: "Deep Page", in: l4.folderURL))

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        return (nexus, idx, pt.id, l1.id, l2.id, l3.id, l4.id, l3PageFM.id)
    }

    // MARK: - Deep recursion

    @Test func fourDeepFixtureIndexesAllSets() async throws {
        let fx = try await setupFourDeep()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        let setCount = try await fx.idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_sets") ?? -1
        }
        // L1, L2, L3, L4
        #expect(setCount == 4)
    }

    @Test func eachSetRowHasExactlyOneParentColumn() async throws {
        let fx = try await setupFourDeep()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        let rows = try await fx.idx.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, parent_type_id, parent_set_id FROM page_sets")
        }
        for row in rows {
            let typeID: String? = row["parent_type_id"]
            let setID: String? = row["parent_set_id"]
            // Exactly one of them is non-null
            #expect((typeID == nil) != (setID == nil), "Set row \(row["id"] as String) must have exactly one parent column set")
        }
    }

    @Test func depthOneSetsHaveParentTypeID() async throws {
        let fx = try await setupFourDeep()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        let l1Row = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM page_sets WHERE id = ?", arguments: [fx.l1ID])
        }
        #expect(l1Row?["parent_type_id"] as String? == fx.typeID)
        #expect(l1Row?["parent_set_id"] as String? == nil)
    }

    @Test func deeperSetsHaveParentSetID() async throws {
        let fx = try await setupFourDeep()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        let l2Row = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM page_sets WHERE id = ?", arguments: [fx.l2ID])
        }
        #expect(l2Row?["parent_set_id"] as String? == fx.l1ID)
        #expect(l2Row?["parent_type_id"] as String? == nil)

        let l3Row = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM page_sets WHERE id = ?", arguments: [fx.l3ID])
        }
        #expect(l3Row?["parent_set_id"] as String? == fx.l2ID)
        #expect(l3Row?["parent_type_id"] as String? == nil)

        let l4Row = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM page_sets WHERE id = ?", arguments: [fx.l4ID])
        }
        #expect(l4Row?["parent_set_id"] as String? == fx.l3ID)
        #expect(l4Row?["parent_type_id"] as String? == nil)
    }

    @Test func depthThreePageIndexesWithImmediateParentSetID() async throws {
        let fx = try await setupFourDeep()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        let pageRow = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [fx.l3PageID])
        }
        // L3 page's immediate parent is L3 (depth-3 set)
        #expect(pageRow?["page_set_id"] as String? == fx.l3ID)
        #expect(pageRow?["page_type_id"] as String? == fx.typeID)
    }

    // MARK: - .pageSet query filter

    @Test func pageSetQueryFilterReturnsSetPages() async throws {
        let fx = try await setupFourDeep()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        let query = IndexQuery(fx.idx)
        // .pageSet(l3ID) should return only the L3 page, not the L4 page
        let results = try await query.filter([], in: .pageSet(fx.l3ID))
        #expect(results.count == 1)
        #expect(results.first?.id == fx.l3PageID)
    }

    @Test func pageSetQueryFilterIsEmptyForSetWithNoDirectPages() async throws {
        let fx = try await setupFourDeep()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        let query = IndexQuery(fx.idx)
        // L2 has no direct pages (only L3 as a child set)
        let results = try await query.filter([], in: .pageSet(fx.l2ID))
        #expect(results.isEmpty)
    }
}
