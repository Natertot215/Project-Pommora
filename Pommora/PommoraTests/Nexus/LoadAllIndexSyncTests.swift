//
//  LoadAllIndexSyncTests.swift
//  PommoraTests
//
//  Regression coverage for: "FOREIGN KEY constraint failed - while
//  executing `INSERT OR REPLACE INTO pages...`" toast that surfaced
//  when CRUD ran against entities loaded from disk that the index DB
//  had no record of (adoption / external-folder scenarios). loadAll
//  on PageTypeManager now defensively upserts every in-memory parent
//  entity into the index so subsequent CRUD upserts always find their
//  FK target.
//

import Foundation
import GRDB
import Testing

@testable import Pommora

@MainActor
@Suite("loadAll syncs parents to index")
struct LoadAllIndexSyncTests {

    // MARK: - PageType / PageCollection sync

    /// Simulates the adoption / external-folder scenario: a PageType folder
    /// + sidecar lives on disk but was never created via the app's CRUD
    /// (so upsertPageType never ran). loadAll should defensively upsert
    /// it to the index so later page CRUD doesn't FK-fail.
    @Test func pageTypeManagerLoadAllSyncsToIndex() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        // Write a PageType sidecar directly to disk — bypassing
        // createPageType (which would upsert via CRUD). This mirrors the
        // post-adoption / external-folder state.
        let vaultID = ULID.generate()
        let folderName = "Adopted Vault"
        let folder = NexusPaths.vaultFolderURL(forTitle: folderName, in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pageType = PageType(
            id: vaultID,
            title: folderName,
            icon: nil,
            properties: [],
            views: [],
            modifiedAt: Date()
        )
        let sidecarURL = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        try pageType.save(to: sidecarURL)

        // Confirm the DB starts empty.
        let initialCount = try await index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_types") ?? -1
        }
        #expect(initialCount == 0)

        // Wire IndexUpdater + load.
        let manager = PageTypeManager(nexus: nexus)
        manager.indexUpdater = IndexUpdater(index)
        await manager.loadAll()

        // Post-loadAll: page_types should now contain the vault.
        let postCount = try await index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_types WHERE id = ?", arguments: [vaultID]) ?? -1
        }
        #expect(postCount == 1)

        // And subsequent upsertPage with this vault.id must NOT throw a
        // foreign-key violation — this is the original symptom.
        let pageMeta = PageMeta(
            id: ULID.generate(),
            title: "TestPage",
            url: folder.appendingPathComponent("TestPage.md"),
            frontmatter: PageFrontmatter(id: ULID.generate(), icon: nil, tier1: [], tier2: [], tier3: [], properties: [:], createdAt: Date())
        )
        let updater = IndexUpdater(index)
        try updater.upsertPage(pageMeta, pageTypeID: vaultID, pageCollectionID: nil)

        // Verify the page row landed. Hoist pageMeta.id to a local `let`
        // because the @MainActor-isolated suite's properties can't be
        // captured inside the @Sendable dbQueue closure (Swift 6 strict
        // concurrency, quirk #5).
        let pageID = pageMeta.id
        let pageCount = try await index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pages WHERE id = ?", arguments: [pageID]) ?? -1
        }
        #expect(pageCount == 1)
    }

    /// Same scenario for a PageCollection nested inside a PageType — the
    /// loadAll pair (PageTypeManager then PageSetManager) must sync BOTH levels
    /// so page CRUD into a collection doesn't FK-fail on `page_collection_id`.
    @Test func pageTypeManagerLoadAllSyncsCollectionsToo() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        // PageType folder + sidecar on disk.
        let vaultID = ULID.generate()
        let vaultName = "Adopted Vault"
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: vaultName, in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        let pageType = PageType(id: vaultID, title: vaultName, icon: nil, properties: [], views: [], modifiedAt: Date())
        try pageType.save(to: vaultFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))

        // PageCollection sub-folder + sidecar on disk.
        let collID = ULID.generate()
        let collName = "Adopted Collection"
        let collFolder = vaultFolder.appendingPathComponent(collName, isDirectory: true)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let collection = PageCollection(id: collID, typeID: vaultID, title: collName, folderURL: collFolder, modifiedAt: Date())
        try collection.save(to: collFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))

        // Wire + load: collections are owned by PageSetManager.
        let manager = PageTypeManager(nexus: nexus)
        manager.indexUpdater = IndexUpdater(index)
        let setManager = PageSetManager(nexus: nexus)
        setManager.indexUpdater = IndexUpdater(index)
        setManager.pageTypeProvider = { [weak manager] in manager?.types ?? [] }
        manager.pageSetManager = setManager
        await manager.loadAll()
        await setManager.loadAll(types: manager.types)

        // Both type AND collection should be in the index now.
        let counts = try await index.dbQueue.read { db -> (Int, Int) in
            let t = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_types WHERE id = ?", arguments: [vaultID]) ?? -1
            let c = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_collections WHERE id = ?", arguments: [collID]) ?? -1
            return (t, c)
        }
        #expect(counts.0 == 1)
        #expect(counts.1 == 1)

        // Subsequent upsertPage into this collection MUST succeed.
        let pageMeta = PageMeta(
            id: ULID.generate(),
            title: "TestPage",
            url: collFolder.appendingPathComponent("TestPage.md"),
            frontmatter: PageFrontmatter(id: ULID.generate(), icon: nil, tier1: [], tier2: [], tier3: [], properties: [:], createdAt: Date())
        )
        try IndexUpdater(index).upsertPage(pageMeta, pageTypeID: vaultID, pageCollectionID: collID)
    }

    // MARK: - Project (tier-3 contexts) sync

    /// A free-standing Project folder + sidecar on disk (adoption / external-
    /// folder state) must be upserted into the `contexts` table as tier 3 by
    /// ProjectManager.loadAll, so the tier-3 picker can surface it.
    @Test func projectManagerLoadAllSyncsTier3ContextRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        // Write a Project folder + sidecar directly to disk (bypassing CRUD).
        let projectID = ULID.generate()
        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/projects/Adopted Project", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let project = Project(id: projectID, title: "Adopted Project", icon: nil, blocks: [], modifiedAt: Date())
        try project.save(to: folder.appendingPathComponent("_project.json"))

        let manager = ProjectManager(nexus: nexus)
        manager.indexUpdater = IndexUpdater(index)
        await manager.loadAll()

        let count = try await index.dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM contexts WHERE id = ? AND tier = 3",
                arguments: [projectID]) ?? -1
        }
        #expect(count == 1)
    }

    // MARK: - Idempotency

    /// loadAll runs at startup; if IndexBuilder already populated the DB,
    /// the loadAll sync is a no-op (INSERT OR REPLACE just rewrites the
    /// same row). This test runs loadAll twice and asserts the row count
    /// stays stable — i.e. no duplicates, no FK fail on the second pass.
    @Test func loadAllIsIdempotent() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let vaultID = ULID.generate()
        let folder = NexusPaths.vaultFolderURL(forTitle: "Vault", in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pageType = PageType(id: vaultID, title: "Vault", icon: nil, properties: [], views: [], modifiedAt: Date())
        try pageType.save(to: folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))

        let manager = PageTypeManager(nexus: nexus)
        manager.indexUpdater = IndexUpdater(index)
        await manager.loadAll()
        await manager.loadAll()  // second pass should be a no-op

        let count = try await index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_types WHERE id = ?", arguments: [vaultID]) ?? -1
        }
        #expect(count == 1)
    }
}
