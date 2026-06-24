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
        let typeManager: PageCollectionManager
        let setManager: PageSetManager
        let pageCollection: PageCollection
        let collection: PageSet
    }

    /// Vault "Notes" + Collection "Inbox" via CRUD; both managers loaded.
    private func makeFixture(indexUpdater: IndexUpdater? = nil) async throws -> Fixture {
        let nexus = try TempNexus.make()
        let typeManager = PageCollectionManager(nexus: nexus)
        typeManager.indexUpdater = indexUpdater
        let setManager = PageSetManager(nexus: nexus)
        setManager.indexUpdater = indexUpdater
        setManager.pageTypeProvider = { [weak typeManager] in typeManager?.types ?? [] }
        typeManager.pageSetManager = setManager
        await typeManager.loadAll()
        try await typeManager.createPageCollection(name: "Notes", icon: nil)
        let pageCollection = typeManager.types.first!
        try await typeManager.createPageCollection(name: "Inbox", inPageCollection: pageCollection)
        let collection = typeManager.pageCollections(in: pageCollection).first!
        await setManager.loadAll(types: typeManager.types)
        return Fixture(
            nexus: nexus, typeManager: typeManager, setManager: setManager,
            pageCollection: pageCollection, collection: collection
        )
    }

    /// Same fixture with a live SQLite index wired into both managers, so the
    /// Vault + Collection CRUD upserts populate the FK parents.
    private func makeIndexedFixture() async throws -> (fx: Fixture, index: PommoraIndex) {
        let nexus = try TempNexus.make()
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(index)
        let typeManager = PageCollectionManager(nexus: nexus)
        typeManager.indexUpdater = updater
        let setManager = PageSetManager(nexus: nexus)
        setManager.indexUpdater = updater
        setManager.pageTypeProvider = { [weak typeManager] in typeManager?.types ?? [] }
        typeManager.pageSetManager = setManager
        await typeManager.loadAll()
        try await typeManager.createPageCollection(name: "Notes", icon: nil)
        let pageCollection = typeManager.types.first!
        try await typeManager.createPageCollection(name: "Inbox", inPageCollection: pageCollection)
        let collection = typeManager.pageCollections(in: pageCollection).first!
        await setManager.loadAll(types: typeManager.types)
        let fx = Fixture(
            nexus: nexus, typeManager: typeManager, setManager: setManager,
            pageCollection: pageCollection, collection: collection
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
        #expect(set.parentID == fx.collection.id)
        #expect(fx.setManager.pageSets(in: fx.collection).map(\.id) == [set.id])

        // A fresh manager loads the same Set back from disk.
        let reloaded = PageSetManager(nexus: fx.nexus)
        await reloaded.loadAll(types: fx.typeManager.types)
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

        let collSidecar = try PageSet.load(
            from: fx.collection.folderURL.appendingPathComponent(
                NexusPaths.pageCollectionSidecarFilename))
        #expect(collSidecar.setOrder == ids)

        // A fresh load resolves the persisted order.
        let reloaded = PageSetManager(nexus: fx.nexus)
        await reloaded.loadAll(types: fx.typeManager.types)
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

        // The deleted Set's index row is gone. Depth-1 Collections share the
        // `page_sets` table (parent_collection_id set, parent_set_id NULL), so count only
        // depth-2+ Sets (parent_set_id NOT NULL) to assert the Set's row left.
        let count = try await index.dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM page_sets WHERE parent_set_id IS NOT NULL") ?? -1
        }
        #expect(count == 0)
    }

    // MARK: - Delete (.setOnly)

    @Test("deletePageSet(.setOnly) re-homes all descendant pages and re-points index rows")
    func deleteSetOnly() async throws {
        let (fx, index) = try await makeIndexedFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        let set = try await fx.setManager.createPageSet(name: "Drafts", in: fx.collection)
        let pageID = try writePage(titled: "Inside", in: set.folderURL)
        // Depth-3+ folders roll up INTO the Set, so dissolving it must flatten
        // their pages into the Collection root too — not just direct children.
        let nestedFolder = set.folderURL.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
        _ = try writePage(titled: "Deep", in: nestedFolder)

        // Index the page under the Set first — the state being re-pointed.
        let pageURL = NexusPaths.pageFileURL(forTitle: "Inside", in: set.folderURL)
        let pf = try PageFile.load(from: pageURL)
        try IndexUpdater(index).upsertPage(
            PageMeta(id: pageID, title: "Inside", url: pageURL, frontmatter: pf.frontmatter),
            pageCollectionID: fx.pageCollection.id, pageSetID: set.id)

        try await fx.setManager.deletePageSet(set, mode: .setOnly)

        // Both pages re-homed (flattened) into the Collection folder on disk;
        // Set folder gone.
        let rehomed = NexusPaths.pageFileURL(forTitle: "Inside", in: fx.collection.folderURL)
        let rehomedDeep = NexusPaths.pageFileURL(forTitle: "Deep", in: fx.collection.folderURL)
        #expect(FileManager.default.fileExists(atPath: rehomed.path))
        #expect(FileManager.default.fileExists(atPath: rehomedDeep.path))
        #expect(!FileManager.default.fileExists(atPath: set.folderURL.path))
        #expect(fx.setManager.pageSets(in: fx.collection).isEmpty)

        // Index: page re-pointed (set cleared); the Set's row is gone. Depth-1
        // Collections share `page_sets` (parent_collection_id set), so count only
        // depth-2+ Sets (parent_set_id NOT NULL) to assert the Set's row left.
        let vaultID = fx.pageCollection.id
        let row = try await index.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [pageID])
        }
        #expect(row?["page_collection_id"] as String? == vaultID)
        #expect(row?["page_set_id"] as String? == nil)
        let setCount = try await index.dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM page_sets WHERE parent_set_id IS NOT NULL") ?? -1
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

    @Test("deletePageSet(.setOnly) throws when flattening would collide two nested pages")
    func deleteSetOnlyBatchCollision() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        // Same title at the Set root AND inside a nested folder — flattening
        // both into the Collection root would collide them with each other.
        let set = try await fx.setManager.createPageSet(name: "Drafts", in: fx.collection)
        _ = try writePage(titled: "Same", in: set.folderURL)
        let nestedFolder = set.folderURL.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
        _ = try writePage(titled: "Same", in: nestedFolder)

        await #expect(throws: PageSetValidator.ValidationError.duplicateTitle) {
            try await fx.setManager.deletePageSet(set, mode: .setOnly)
        }

        // Nothing moved; the Set survives intact.
        #expect(FileManager.default.fileExists(atPath: set.folderURL.path))
        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Same", in: fx.collection.folderURL).path))
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

        await fx.setManager.loadAll(types: fx.typeManager.types)

        #expect(FileManager.default.fileExists(atPath: sidecarURL.path))
        let sets = fx.setManager.pageSets(in: fx.collection)
        #expect(sets.count == 1)
        #expect(sets.first?.title == "Drafts")
        #expect(sets.first?.parentID == fx.collection.id)
    }

    @Test("loadAll heals collection_id drift")
    func collectionIDDriftHeal() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        let set = try await fx.setManager.createPageSet(name: "Drafts", in: fx.collection)
        // Re-point the sidecar at a vanished Collection id (re-adoption scenario).
        let sidecarURL = set.folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
        var drifted = try PageSet.load(from: sidecarURL)
        drifted.parentID = ULID.generate()
        try drifted.save(to: sidecarURL)

        await fx.setManager.loadAll(types: fx.typeManager.types)

        #expect(fx.setManager.pageSets(in: fx.collection).first?.parentID == fx.collection.id)
        #expect(try PageSet.load(from: sidecarURL).parentID == fx.collection.id)
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
            id: ULID.generate(), parentID: fx.collection.id, title: "Drafts",
            folderURL: setFolder, modifiedAt: Date()
        )
        try set.save(to: setFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))

        let setID = set.id
        let pre = try await index.dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM page_sets WHERE id = ?", arguments: [setID]) ?? -1
        }
        #expect(pre == 0)

        await fx.setManager.loadAll(types: fx.typeManager.types)

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
            pageCollectionID: fx.pageCollection.id, pageSetID: setID)
        let rowSetID = try await index.dbQueue.read { db in
            try String.fetchOne(
                db, sql: "SELECT page_set_id FROM pages WHERE id = ?", arguments: [pageID])
        }
        #expect(rowSetID == setID)
    }

    // MARK: - Folder-URL rebuild on parent rename

    @Test("Collection rename rebuilds child Set URLs")
    func collectionRenameRebuildsSetURLs() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        let set = try await fx.setManager.createPageSet(name: "Drafts", in: fx.collection)
        try await fx.typeManager.renamePageCollection(fx.collection, to: "Archive")

        let renamed = fx.typeManager.pageCollections(in: fx.pageCollection).first!
        let cached = fx.setManager.pageSets(in: renamed).first!
        #expect(cached.id == set.id)
        #expect(cached.folderURL.path == renamed.folderURL.appendingPathComponent("Drafts").path)
        // The Set folder really travelled with its parent on disk.
        #expect(
            FileManager.default.fileExists(
                atPath: cached.folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename).path))
    }

    @Test("Page Type rename rebuilds each Collection's child Set URLs")
    func typeRenameRebuildsSetURLs() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        let set = try await fx.setManager.createPageSet(name: "Drafts", in: fx.collection)
        try await fx.typeManager.renamePageCollection(fx.pageCollection, to: "Journal")

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

    // MARK: - Recursive discovery

    @Test("loadAll discovers arbitrarily nested PageSets and chains parentIDs correctly")
    func recursiveSetDiscovery() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        // Build: Notes/Inbox/SetA/SubB/SubC/page.md — each subfolder has a _pageset.json.
        let setAFolder = fx.collection.folderURL.appendingPathComponent("SetA", isDirectory: true)
        let subBFolder = setAFolder.appendingPathComponent("SubB", isDirectory: true)
        let subCFolder = subBFolder.appendingPathComponent("SubC", isDirectory: true)
        try FileManager.default.createDirectory(at: subCFolder, withIntermediateDirectories: true)

        let setA = PageSet(id: ULID.generate(), parentID: fx.collection.id, title: "SetA", folderURL: setAFolder, modifiedAt: Date())
        let subB = PageSet(id: ULID.generate(), parentID: setA.id, title: "SubB", folderURL: subBFolder, modifiedAt: Date())
        let subC = PageSet(id: ULID.generate(), parentID: subB.id, title: "SubC", folderURL: subCFolder, modifiedAt: Date())

        try setA.save(to: setAFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        try subB.save(to: subBFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        try subC.save(to: subCFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))

        _ = try writePage(titled: "page", in: subCFolder)

        await fx.setManager.loadAll(types: fx.typeManager.types)

        let setsUnderCollection = fx.setManager.pageSets(in: fx.collection)
        let loadedA = try #require(setsUnderCollection.first(where: { $0.title == "SetA" }))
        #expect(loadedA.parentID == fx.collection.id)

        let setsUnderA = fx.setManager.pageSets(in: loadedA)
        let loadedB = try #require(setsUnderA.first(where: { $0.title == "SubB" }))
        #expect(loadedB.parentID == loadedA.id)

        let setsUnderB = fx.setManager.pageSets(in: loadedB)
        let loadedC = try #require(setsUnderB.first(where: { $0.title == "SubC" }))
        #expect(loadedC.parentID == loadedB.id)

        // A page in SubC is reachable via its folder URL.
        let pageURL = NexusPaths.pageFileURL(forTitle: "page", in: loadedC.folderURL)
        #expect(FileManager.default.fileExists(atPath: pageURL.path))
    }
}
