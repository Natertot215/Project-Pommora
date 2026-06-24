import Foundation
import GRDB
import Testing

@testable import Pommora

/// TDD tests for task 2.4 — v16 schema rename.
///
/// Proves:
/// - `page_collections` is the top-tier table (formerly `page_types`).
/// - `page_sets` rows carry exactly one of `parent_collection_id` / `parent_set_id`.
/// - Every page indexes with `page_collection_id` (top-tier vault) + `page_set_id`
///   (immediate set, nullable).
/// - A `.pageCollection` filter returns only top-level pages; a `.pageSet` filter
///   returns only that set's direct pages.
@Suite("SchemaV16Rename")
@MainActor
struct SchemaV16RenameTests {

    // MARK: - Fixture

    /// Builds:
    ///   Vault (page_collections)
    ///   └── Depth1 (page_sets, parent_collection_id = vault)
    ///       └── Depth2 (page_sets, parent_set_id = depth1)
    ///           └── Deep Page.md
    ///       └── Shallow Page.md    ← direct child of Depth1
    ///   └── Root Page.md           ← direct child of vault (no set)
    private func setup() async throws -> (
        nexus: Nexus, idx: PommoraIndex,
        vaultID: String, depth1ID: String, depth2ID: String,
        rootPageID: String, shallowPageID: String, deepPageID: String
    ) {
        let nexus = try TempNexus.make()

        let collectionManager = PageCollectionManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageTypeProvider = { [weak collectionManager] in collectionManager?.types ?? [] }
        collectionManager.pageSetManager = setManager
        await collectionManager.loadAll()
        try await collectionManager.createPageCollection(name: "Vault", icon: nil)
        let vault = collectionManager.types.first!

        // Depth-1: depth-1 set created as a collection (_pagecollection.json sidecar).
        try await collectionManager.createPageCollection(name: "Depth1", inPageCollection: vault)
        let depth1 = collectionManager.pageCollections(in: vault).first!

        // Depth-2: a raw PageSet inside Depth1.
        let depth2Folder = depth1.folderURL.appendingPathComponent("Depth2", isDirectory: true)
        try FileManager.default.createDirectory(at: depth2Folder, withIntermediateDirectories: true)
        let depth2 = PageSet(
            id: ULID.generate(), parentID: depth1.id, title: "Depth2",
            folderURL: depth2Folder, modifiedAt: Date()
        )
        try depth2.save(to: depth2Folder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))

        // Pages at each depth.
        let now = Date()
        func writePage(title: String, in folder: URL) throws -> String {
            let fm = PageFrontmatter(
                id: ULID.generate(), icon: nil,
                tier1: [], tier2: [], tier3: [],
                properties: [:], createdAt: now, modifiedAt: now
            )
            try AtomicYAMLMarkdown.write(
                frontmatter: fm, body: "",
                to: NexusPaths.pageFileURL(forTitle: title, in: folder))
            return fm.id
        }

        let vaultFolder = NexusPaths.pageTypeFolderURL(forTitle: vault.title, in: nexus)
        let rootPageID = try writePage(title: "Root Page", in: vaultFolder)
        let shallowPageID = try writePage(title: "Shallow Page", in: depth1.folderURL)
        let deepPageID = try writePage(title: "Deep Page", in: depth2Folder)

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        return (nexus, idx, vault.id, depth1.id, depth2.id, rootPageID, shallowPageID, deepPageID)
    }

    // MARK: - Schema shape

    @Test func topTierLandsInPageCollectionsTable() async throws {
        let fx = try await setup()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        let count = try await fx.idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_collections WHERE id = ?",
                             arguments: [fx.vaultID]) ?? 0
        }
        #expect(count == 1, "vault must land in page_collections")
    }

    @Test func depth1SetHasParentCollectionID() async throws {
        let fx = try await setup()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        let row = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT parent_collection_id, parent_set_id FROM page_sets WHERE id = ?",
                             arguments: [fx.depth1ID])
        }
        #expect(row?["parent_collection_id"] as String? == fx.vaultID)
        #expect(row?["parent_set_id"] as String? == nil)
    }

    @Test func depth2SetHasParentSetID() async throws {
        let fx = try await setup()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        let row = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT parent_collection_id, parent_set_id FROM page_sets WHERE id = ?",
                             arguments: [fx.depth2ID])
        }
        #expect(row?["parent_collection_id"] as String? == nil)
        #expect(row?["parent_set_id"] as String? == fx.depth1ID)
    }

    @Test func everySetRowHasExactlyOneParentColumn() async throws {
        let fx = try await setup()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        let rows = try await fx.idx.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, parent_collection_id, parent_set_id FROM page_sets")
        }
        for row in rows {
            let collectionID: String? = row["parent_collection_id"]
            let setID: String? = row["parent_set_id"]
            #expect(
                (collectionID == nil) != (setID == nil),
                "set row \(row["id"] as String) must have exactly one parent column"
            )
        }
    }

    // MARK: - Page FKs

    @Test func rootPageIndexesWithVaultIDAndNoSet() async throws {
        let fx = try await setup()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        let row = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT page_collection_id, page_set_id FROM pages WHERE id = ?",
                             arguments: [fx.rootPageID])
        }
        #expect(row?["page_collection_id"] as String? == fx.vaultID)
        #expect(row?["page_set_id"] as String? == nil)
    }

    @Test func shallowPageIndexesWithVaultIDAndDepth1SetID() async throws {
        let fx = try await setup()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        let row = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT page_collection_id, page_set_id FROM pages WHERE id = ?",
                             arguments: [fx.shallowPageID])
        }
        #expect(row?["page_collection_id"] as String? == fx.vaultID)
        #expect(row?["page_set_id"] as String? == fx.depth1ID)
    }

    @Test func deepPageIndexesWithVaultIDAndDepth2SetID() async throws {
        let fx = try await setup()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        let row = try await fx.idx.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT page_collection_id, page_set_id FROM pages WHERE id = ?",
                             arguments: [fx.deepPageID])
        }
        #expect(row?["page_collection_id"] as String? == fx.vaultID)
        #expect(row?["page_set_id"] as String? == fx.depth2ID)
    }

    // MARK: - Query filters

    @Test func topTierFilterReturnsOnlyRootPageForVault() async throws {
        let fx = try await setup()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        let results = try await IndexQuery(fx.idx).filter([], in: .pageCollection(fx.vaultID))
        #expect(results.count == 1)
        #expect(results.first?.id == fx.rootPageID, "pageCollection filter must return only vault-root pages, not set pages")
    }

    @Test func pageSetFilterReturnsOnlyImmediateChildren() async throws {
        let fx = try await setup()
        defer { TempNexus.cleanup(fx.nexus) }

        try await IndexBuilder.populate(index: fx.idx, from: fx.nexus)

        let depth1Results = try await IndexQuery(fx.idx).filter([], in: .pageSet(fx.depth1ID))
        #expect(depth1Results.count == 1)
        #expect(depth1Results.first?.id == fx.shallowPageID, "depth-1 set filter must return only its direct page")

        let depth2Results = try await IndexQuery(fx.idx).filter([], in: .pageSet(fx.depth2ID))
        #expect(depth2Results.count == 1)
        #expect(depth2Results.first?.id == fx.deepPageID, "depth-2 set filter must return only its direct page")
    }
}
