import Foundation
import Testing
import GRDB

@testable import Pommora

/// Pages-side CRUD tests for PageContentManager (PageSet-scoped).
@MainActor
@Suite("PageContentManager")
struct PageContentManagerTests {

    @Test("createPage writes .md with frontmatter scaffold")
    func createPage() async throws {
        let (nexus, collection, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, pageCollection: collection)
        let url = NexusPaths.pageFileURL(forTitle: "Notes", in: coll.folderURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let pages = manager.pages(inCollection: coll)
        #expect(pages.count == 1)
        #expect(pages.first?.title == "Notes")

        let loaded = try PageFile.load(from: url)
        #expect(!loaded.frontmatter.id.isEmpty)
        #expect(loaded.body == "")
        #expect(loaded.frontmatter.createdAt.timeIntervalSince1970 > 0)
    }

    @Test("renamePage moves file + updates pages list")
    func renamePage() async throws {
        let (nexus, collection, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        try await manager.createPage(name: "Notes", in: coll, pageCollection: collection)
        let page = manager.pages(inCollection: coll).first!

        try await manager.renamePage(page, to: "Ideas", in: coll, pageCollection: collection)
        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Notes", in: coll.folderURL).path
            ))
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Ideas", in: coll.folderURL).path
            ))
        #expect(manager.pages(inCollection: coll).first?.title == "Ideas")
    }

    @Test("deletePage removes file")
    func deletes() async throws {
        let (nexus, collection, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        try await manager.createPage(name: "P", in: coll, pageCollection: collection)
        let page = manager.pages(inCollection: coll).first!
        let pageURL = NexusPaths.pageFileURL(forTitle: "P", in: coll.folderURL)

        try await manager.deletePage(page, inCollection: coll)

        #expect(manager.pages(inCollection: coll).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: pageURL.path))

        // File now in .trash, preserving relative path under nexus root
        // (flatlayout: PageCollection + PageSet folders live at the nexus root).
        let trashPage = NexusPaths.trashDir(in: nexus).appendingPathComponent("V/C/P.md")
        #expect(FileManager.default.fileExists(atPath: trashPage.path))
    }

    @Test("loadAll discovers existing .md in a PageSet")
    func loadExisting() async throws {
        let (nexus, _, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        try FixtureFiles.write(
            "---\nid: 01HPRE\ncreated_at: 2025-01-01T00:00:00Z\n---\n\nbody\n",
            to: NexusPaths.pageFileURL(forTitle: "Pre", in: coll.folderURL)
        )

        await manager.loadAll(forCollection: coll)
        #expect(manager.pages(inCollection: coll).count == 1)
    }

    // MARK: - resolveParent (index-based path)

    /// resolveParent uses the index to find the collection even when the page has
    /// never been loaded into the manager's in-memory arrays.
    @Test("resolveParent resolves vault via index when page not in memory")
    func resolveParentViaIndex() async throws {
        let (nexus, collection, _, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        // Open a fresh index, seed it with the collection type + an unloaded page.
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        let pageID = ULID.generate()
        let ts = ISO8601DateFormatter().string(from: Date())
        let collectionID = collection.id
        let collectionTitle = collection.title
        try await index.dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO page_collections (id, title, modified_at) VALUES (?, ?, ?)",
                arguments: [collectionID, collectionTitle, ts])
            try db.execute(
                sql: "INSERT INTO pages (id, page_collection_id, title, modified_at) VALUES (?, ?, ?, ?)",
                arguments: [pageID, collectionID, "Unloaded", ts])
        }
        manager.indexUpdater = IndexUpdater(index)

        // Build a PageCollectionManager so resolveParent can match the collection ID.
        let collectionManager = PageCollectionManager(nexus: nexus)
        await collectionManager.loadAll()

        // Confirm the page is NOT in the manager's in-memory arrays.
        #expect(manager.pages(in: collection).isEmpty)

        let pageURL = NexusPaths.pageFileURL(
            forTitle: "Unloaded",
            in: NexusPaths.collectionFolderURL(forTitle: collection.title, in: nexus))
        let fm = PageFrontmatter(
            id: pageID, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date())
        let page = PageMeta(id: pageID, title: "Unloaded", url: pageURL, frontmatter: fm)

        let result = manager.resolveParent(for: page, collectionManager: collectionManager)
        #expect(result?.pageCollection.id == collection.id)
        #expect(result?.collection == nil)
    }

    /// resolveParent resolves collection + collection via index.
    @Test("resolveParent resolves vault and collection via index")
    func resolveParentWithCollectionViaIndex() async throws {
        let (nexus, collection, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        let pageID = ULID.generate()
        let ts = ISO8601DateFormatter().string(from: Date())
        let collectionID = collection.id
        let collectionTitle = collection.title
        let collID = coll.id
        let collTitle = coll.title
        try await index.dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO page_collections (id, title, modified_at) VALUES (?, ?, ?)",
                arguments: [collectionID, collectionTitle, ts])
            try db.execute(
                sql: "INSERT OR IGNORE INTO page_sets (id, parent_collection_id, title, modified_at) VALUES (?, ?, ?, ?)",
                arguments: [collID, collectionID, collTitle, ts])
            try db.execute(
                sql: "INSERT INTO pages (id, page_collection_id, page_set_id, title, modified_at) VALUES (?, ?, ?, ?, ?)",
                arguments: [pageID, collectionID, collID, "InColl", ts])
        }
        manager.indexUpdater = IndexUpdater(index)

        let collectionManager = PageCollectionManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageCollectionProvider = { [weak collectionManager] in collectionManager?.types ?? [] }
        collectionManager.pageSetManager = setManager
        await collectionManager.loadAll()
        await setManager.loadAll(types: collectionManager.types)
        #expect(manager.pages(inCollection: coll).isEmpty)

        let fm = PageFrontmatter(
            id: pageID, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date())
        let page = PageMeta(
            id: pageID, title: "InColl",
            url: NexusPaths.pageFileURL(forTitle: "InColl", in: coll.folderURL),
            frontmatter: fm)

        let result = manager.resolveParent(for: page, collectionManager: collectionManager)
        #expect(result?.pageCollection.id == collection.id)
        #expect(result?.collection?.id == coll.id)
    }

    /// URL-based fallback fires when no index is wired (indexUpdater == nil).
    @Test("resolveParent falls back to URL matching when no index")
    func resolveParentURLFallback() async throws {
        let (nexus, collection, _, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        // manager.indexUpdater is nil — no index available.

        let collectionManager = PageCollectionManager(nexus: nexus)
        await collectionManager.loadAll()

        let pageURL = NexusPaths.pageFileURL(
            forTitle: "AnyPage",
            in: NexusPaths.collectionFolderURL(forTitle: collection.title, in: nexus))
        let fm = PageFrontmatter(
            id: ULID.generate(), icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date())
        let page = PageMeta(id: ULID.generate(), title: "AnyPage", url: pageURL, frontmatter: fm)

        let result = manager.resolveParent(for: page, collectionManager: collectionManager)
        #expect(result?.pageCollection.id == collection.id)
    }

    private func setup() async throws -> (Nexus, PageCollection, PageSet, PageContentManager) {
        let nexus = try TempNexus.make()
        let collection = PageCollection(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        let collectionFolder = NexusPaths.collectionFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: collectionFolder, withIntermediateDirectories: true)
        try collection.save(to: NexusPaths.collectionMetadataURL(forTitle: "V", in: nexus))

        let collFolder = NexusPaths.setFolderURL(forTitle: "C", inCollectionTitled: "V", in: nexus)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = PageSet(
            id: ULID.generate(),
            parentID: collection.id,
            title: "C",
            folderURL: collFolder,
            modifiedAt: Date()
        )
        try coll.save(to: collFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, collection, coll, manager)
    }
}
