import Foundation
import GRDB
import Testing

@testable import Pommora

@MainActor
@Suite("PageSetManager")
struct PageSetManagerTests {

    // MARK: - Fixtures

    private struct Fixture {
        let nexus: Nexus
        let typeManager: PageTypeManager
        let setManager: PageSetManager
        let pageType: PageType
        let collection: PageCollection
    }

    /// Vault "Notes" + Collection "Inbox" via CRUD; both managers loaded.
    private func makeFixture(indexUpdater: IndexUpdater? = nil) async throws -> Fixture {
        let nexus = try TempNexus.make()
        let typeManager = PageTypeManager(nexus: nexus)
        typeManager.indexUpdater = indexUpdater
        await typeManager.loadAll()
        try await typeManager.createPageType(name: "Notes", icon: nil)
        let pageType = typeManager.types.first!
        try await typeManager.createPageCollection(name: "Inbox", inPageType: pageType)
        let collection = typeManager.pageCollections(in: pageType).first!
        let setManager = PageSetManager(nexus: nexus)
        setManager.indexUpdater = indexUpdater
        await setManager.loadAll(collections: [collection])
        return Fixture(
            nexus: nexus, typeManager: typeManager, setManager: setManager,
            pageType: pageType, collection: collection
        )
    }

    /// Same fixture with a live SQLite index wired into both managers, so the
    /// Vault + Collection CRUD upserts populate the FK parents.
    private func makeIndexedFixture() async throws -> (fx: Fixture, index: PommoraIndex) {
        let nexus = try TempNexus.make()
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(index)
        let typeManager = PageTypeManager(nexus: nexus)
        typeManager.indexUpdater = updater
        await typeManager.loadAll()
        try await typeManager.createPageType(name: "Notes", icon: nil)
        let pageType = typeManager.types.first!
        try await typeManager.createPageCollection(name: "Inbox", inPageType: pageType)
        let collection = typeManager.pageCollections(in: pageType).first!
        let setManager = PageSetManager(nexus: nexus)
        setManager.indexUpdater = updater
        await setManager.loadAll(collections: [collection])
        let fx = Fixture(
            nexus: nexus, typeManager: typeManager, setManager: setManager,
            pageType: pageType, collection: collection
        )
        return (fx, index)
    }

    /// Writes a `.md` Page with proper frontmatter into `folder`; returns its id.
    private func writePage(titled title: String, in folder: URL) throws -> String {
        let id = ULID.generate()
        let fm = PageFrontmatter(
            id: id, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date()
        )
        try AtomicYAMLMarkdown.write(
            frontmatter: fm, body: "",
            to: NexusPaths.pageFileURL(forTitle: title, in: folder))
        return id
    }

    // MARK: - Create

    @Test("createPageSet writes folder + _pageset.json and round-trips via loadAll")
    func createPageSet() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        let set = try await fx.setManager.createPageSet(name: "Drafts", in: fx.collection)
        let folder = fx.collection.folderURL.appendingPathComponent("Drafts", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(
            FileManager.default.fileExists(
                atPath: folder.appendingPathComponent(NexusPaths.pageSetSidecarFilename).path))
        #expect(set.collectionID == fx.collection.id)
        #expect(fx.setManager.pageSets(in: fx.collection).map(\.id) == [set.id])

        // A fresh manager loads the same Set back from disk.
        let reloaded = PageSetManager(nexus: fx.nexus)
        await reloaded.loadAll(collections: [fx.collection])
        #expect(reloaded.pageSets(in: fx.collection).map(\.id) == [set.id])
        #expect(reloaded.pageSets(in: fx.collection).first?.title == "Drafts")
    }

    @Test("createPageSet rejects a duplicate title in the same Collection")
    func createDuplicateThrows() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        try await fx.setManager.createPageSet(name: "Drafts", in: fx.collection)
        await #expect(throws: PageSetValidator.ValidationError.duplicateTitle) {
            try await fx.setManager.createPageSet(name: "drafts", in: fx.collection)
        }
        #expect(fx.setManager.pageSets(in: fx.collection).count == 1)
    }

    // MARK: - Rename

    @Test("renamePageSet renames the folder and preserves fields")
    func renamePageSet() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        let set = try await fx.setManager.createPageSet(name: "Drafts", in: fx.collection)
        try await fx.setManager.updatePageSetIcon(set, to: "tray")
        let withIcon = fx.setManager.pageSets(in: fx.collection).first!

        try await fx.setManager.renamePageSet(withIcon, to: "Outbox")

        let newFolder = fx.collection.folderURL.appendingPathComponent("Outbox", isDirectory: true)
        let oldFolder = fx.collection.folderURL.appendingPathComponent("Drafts", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: newFolder.path))
        #expect(!FileManager.default.fileExists(atPath: oldFolder.path))

        let cached = fx.setManager.pageSets(in: fx.collection).first!
        #expect(cached.id == set.id)
        #expect(cached.title == "Outbox")
        #expect(cached.folderURL.path == newFolder.path)
        #expect(cached.icon == "tray")

        // Sidecar at the new path carries the same identity + icon.
        let reloaded = try PageSet.load(
            from: newFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        #expect(reloaded.id == set.id)
        #expect(reloaded.icon == "tray")
    }

    // MARK: - Icon

    @Test("updatePageSetIcon persists to the sidecar")
    func updateIcon() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        let set = try await fx.setManager.createPageSet(name: "Drafts", in: fx.collection)
        try await fx.setManager.updatePageSetIcon(set, to: "tray.full")

        let reloaded = try PageSet.load(
            from: set.folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        #expect(reloaded.icon == "tray.full")
        #expect(fx.setManager.pageSets(in: fx.collection).first?.icon == "tray.full")
    }

    // MARK: - Reorder

    @Test("reorderPageSets persists set_order on the Collection sidecar")
    func reorder() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        let alpha = try await fx.setManager.createPageSet(name: "Alpha", in: fx.collection)
        let beta = try await fx.setManager.createPageSet(name: "Beta", in: fx.collection)
        // The empty-state default is ULID-ascending; two ULIDs minted in the
        // same millisecond tie on the timestamp prefix, so derive the baseline
        // instead of assuming creation order.
        let initial = fx.setManager.pageSets(in: fx.collection).map(\.id)
        #expect(Set(initial) == Set([alpha.id, beta.id]))

        fx.setManager.reorderPageSets(
            in: fx.collection, fromOffsets: IndexSet(integer: 0), toOffset: 2)
        let ids = fx.setManager.pageSets(in: fx.collection).map(\.id)
        #expect(ids == [initial[1], initial[0]])

        let collSidecar = try PageCollection.load(
            from: fx.collection.folderURL.appendingPathComponent(
                NexusPaths.pageCollectionSidecarFilename))
        #expect(collSidecar.setOrder == ids)

        // A fresh load resolves the persisted order.
        let reloaded = PageSetManager(nexus: fx.nexus)
        await reloaded.loadAll(collections: [collSidecar])
        #expect(reloaded.pageSets(in: collSidecar).map(\.id) == ids)
    }

    // MARK: - Delete (.withPages)

    @Test("deletePageSet(.withPages) trashes the folder and deletes the index row")
    func deleteWithPages() async throws {
        let (fx, index) = try await makeIndexedFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        let set = try await fx.setManager.createPageSet(name: "Drafts", in: fx.collection)
        _ = try writePage(titled: "Inside", in: set.folderURL)

        try await fx.setManager.deletePageSet(set, mode: .withPages)

        #expect(!FileManager.default.fileExists(atPath: set.folderURL.path))
        #expect(fx.setManager.pageSets(in: fx.collection).isEmpty)

        // The whole folder (pages included) lands in .trash, relative path preserved.
        let trashedPage = NexusPaths.trashDir(in: fx.nexus)
            .appendingPathComponent("Notes/Inbox/Drafts/Inside.md")
        #expect(FileManager.default.fileExists(atPath: trashedPage.path))

        let count = try await index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_sets") ?? -1
        }
        #expect(count == 0)
    }

    // MARK: - Delete (.setOnly)

    @Test("deletePageSet(.setOnly) re-homes pages and re-points index rows")
    func deleteSetOnly() async throws {
        let (fx, index) = try await makeIndexedFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        let set = try await fx.setManager.createPageSet(name: "Drafts", in: fx.collection)
        let pageID = try writePage(titled: "Inside", in: set.folderURL)

        // Index the page under the Set first — the state being re-pointed.
        let pageURL = NexusPaths.pageFileURL(forTitle: "Inside", in: set.folderURL)
        let pf = try PageFile.load(from: pageURL)
        try IndexUpdater(index).upsertPage(
            PageMeta(id: pageID, title: "Inside", url: pageURL, frontmatter: pf.frontmatter),
            pageTypeID: fx.pageType.id, pageCollectionID: fx.collection.id, pageSetID: set.id)

        try await fx.setManager.deletePageSet(set, mode: .setOnly)

        // Page re-homed into the Collection folder on disk; Set folder gone.
        let rehomed = NexusPaths.pageFileURL(forTitle: "Inside", in: fx.collection.folderURL)
        #expect(FileManager.default.fileExists(atPath: rehomed.path))
        #expect(!FileManager.default.fileExists(atPath: set.folderURL.path))
        #expect(fx.setManager.pageSets(in: fx.collection).isEmpty)

        // Index: page re-pointed (collection kept, set cleared); page_sets row gone.
        let collectionID = fx.collection.id
        let row = try await index.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [pageID])
        }
        #expect(row?["page_collection_id"] as String? == collectionID)
        #expect(row?["page_set_id"] as String? == nil)
        let setCount = try await index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_sets") ?? -1
        }
        #expect(setCount == 0)
    }

    @Test("deletePageSet(.setOnly) throws on title collision and moves nothing")
    func deleteSetOnlyCollision() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        let set = try await fx.setManager.createPageSet(name: "Drafts", in: fx.collection)
        _ = try writePage(titled: "Same", in: set.folderURL)
        _ = try writePage(titled: "Same", in: fx.collection.folderURL)
        // A page that WOULD move cleanly — proves the pre-check stops everything.
        _ = try writePage(titled: "Other", in: set.folderURL)

        await #expect(throws: PageSetValidator.ValidationError.duplicateTitle) {
            try await fx.setManager.deletePageSet(set, mode: .setOnly)
        }

        // Set folder + both its pages untouched; nothing arrived in the Collection.
        #expect(FileManager.default.fileExists(atPath: set.folderURL.path))
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Same", in: set.folderURL).path))
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Other", in: set.folderURL).path))
        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Other", in: fx.collection.folderURL).path))
        #expect(fx.setManager.pageSets(in: fx.collection).count == 1)
    }

    // MARK: - Heal on load

    @Test("loadAll heals a missing _pageset.json")
    func sidecarHeal() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        let set = try await fx.setManager.createPageSet(name: "Drafts", in: fx.collection)
        let sidecarURL = set.folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
        try FileManager.default.removeItem(at: sidecarURL)

        await fx.setManager.loadAll(collections: [fx.collection])

        #expect(FileManager.default.fileExists(atPath: sidecarURL.path))
        let sets = fx.setManager.pageSets(in: fx.collection)
        #expect(sets.count == 1)
        #expect(sets.first?.title == "Drafts")
        #expect(sets.first?.collectionID == fx.collection.id)
    }

    @Test("loadAll heals collection_id drift")
    func collectionIDDriftHeal() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        let set = try await fx.setManager.createPageSet(name: "Drafts", in: fx.collection)
        // Re-point the sidecar at a vanished Collection id (re-adoption scenario).
        let sidecarURL = set.folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
        var drifted = try PageSet.load(from: sidecarURL)
        drifted.collectionID = ULID.generate()
        try drifted.save(to: sidecarURL)

        await fx.setManager.loadAll(collections: [fx.collection])

        #expect(fx.setManager.pageSets(in: fx.collection).first?.collectionID == fx.collection.id)
        #expect(try PageSet.load(from: sidecarURL).collectionID == fx.collection.id)
    }

    // MARK: - Defensive index sync

    @Test("loadAll defensively syncs Finder-created Sets to the index")
    func loadAllIndexSync() async throws {
        let (fx, index) = try await makeIndexedFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        // Lay the Set folder + sidecar down by hand — bypassing createPageSet,
        // so upsertPageSet never ran (Finder / adoption state).
        let setFolder = fx.collection.folderURL.appendingPathComponent("Drafts", isDirectory: true)
        try FileManager.default.createDirectory(at: setFolder, withIntermediateDirectories: true)
        let set = PageSet(
            id: ULID.generate(), collectionID: fx.collection.id, title: "Drafts",
            folderURL: setFolder, modifiedAt: Date()
        )
        try set.save(to: setFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))

        let setID = set.id
        let pre = try await index.dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM page_sets WHERE id = ?", arguments: [setID]) ?? -1
        }
        #expect(pre == 0)

        await fx.setManager.loadAll(collections: [fx.collection])

        let post = try await index.dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM page_sets WHERE id = ?", arguments: [setID]) ?? -1
        }
        #expect(post == 1)

        // A subsequent page upsert carrying the Set id keeps its scope — no FK
        // fallback to a nil set (the original quirk #14 symptom).
        let pageID = try writePage(titled: "Inside", in: setFolder)
        let pageURL = NexusPaths.pageFileURL(forTitle: "Inside", in: setFolder)
        let pf = try PageFile.load(from: pageURL)
        try IndexUpdater(index).upsertPage(
            PageMeta(id: pageID, title: "Inside", url: pageURL, frontmatter: pf.frontmatter),
            pageTypeID: fx.pageType.id, pageCollectionID: fx.collection.id, pageSetID: setID)
        let rowSetID = try await index.dbQueue.read { db in
            try String.fetchOne(
                db, sql: "SELECT page_set_id FROM pages WHERE id = ?", arguments: [pageID])
        }
        #expect(rowSetID == setID)
    }

    // MARK: - Folder-URL rebuild on parent rename

    @Test("Collection rename fires onCollectionFolderChanged and rebuilds Set URLs")
    func collectionRenameRebuildsSetURLs() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }
        let setManager = fx.setManager
        fx.typeManager.onCollectionFolderChanged = { setManager.rebuildFolderURLs(for: $0) }

        let set = try await fx.setManager.createPageSet(name: "Drafts", in: fx.collection)
        try await fx.typeManager.renamePageCollection(fx.collection, to: "Archive")

        let renamed = fx.typeManager.pageCollections(in: fx.pageType).first!
        let cached = fx.setManager.pageSets(in: renamed).first!
        #expect(cached.id == set.id)
        #expect(cached.folderURL.path == renamed.folderURL.appendingPathComponent("Drafts").path)
        // The Set folder really travelled with its parent on disk.
        #expect(
            FileManager.default.fileExists(
                atPath: cached.folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename).path))
    }

    @Test("Page Type rename fires the hook for each rebuilt Collection")
    func typeRenameRebuildsSetURLs() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }
        let setManager = fx.setManager
        fx.typeManager.onCollectionFolderChanged = { setManager.rebuildFolderURLs(for: $0) }

        let set = try await fx.setManager.createPageSet(name: "Drafts", in: fx.collection)
        try await fx.typeManager.renamePageType(fx.pageType, to: "Journal")

        let renamedType = fx.typeManager.types.first!
        let renamedColl = fx.typeManager.pageCollections(in: renamedType).first!
        let cached = fx.setManager.pageSets(in: renamedColl).first!
        #expect(cached.id == set.id)
        #expect(
            cached.folderURL.path == renamedColl.folderURL.appendingPathComponent("Drafts").path)
        #expect(
            FileManager.default.fileExists(
                atPath: cached.folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename).path))
    }
}
