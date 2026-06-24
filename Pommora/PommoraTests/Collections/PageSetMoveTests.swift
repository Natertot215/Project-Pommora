import Foundation
import GRDB
import Testing

@testable import Pommora

/// Whole-Set moves between PageSets (Sets Task 9): same-collection folder
/// relocation with byte-identical Pages, pre-move destination collision,
/// and cross-collection moves with the per-page name-matched property strip
/// (count previewed via `moveStripTotal`).
///
/// Fixtures mirror `PageSetContentTests` (hand-built Collection/Collection/Set
/// folders, index-seeded parents for FK-bearing upserts).
@MainActor
@Suite("PageSetMoveTests")
struct PageSetMoveTests {

    // MARK: - Same-collection move

    @Test("Same-vault moveSet relocates the folder, re-points sidecar + index, keeps Page bytes identical")
    func sameCollectionMove() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(index)

        let collection = try makePageCollection(nexus: nexus, title: "Notes", index: index)
        let source = try makePageCollection(nexus: nexus, title: "Inbox", in: collection, index: index)
        let dest = try makePageCollection(nexus: nexus, title: "Archive", in: collection, index: index)
        let set = try makePageSet(title: "Drafts", in: source, index: index)
        let pageID = try writePage(titled: "Doc", in: set.folderURL)

        let contentManager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        contentManager.indexUpdater = updater
        let setManager = PageSetManager(nexus: nexus)
        setManager.indexUpdater = updater
        await setManager.loadAll(types: [collection])

        // Index the Page under the Set first — the row being re-pointed.
        let pageURL = NexusPaths.pageFileURL(forTitle: "Doc", in: set.folderURL)
        let pf = try PageFile.load(from: pageURL)
        try updater.upsertPage(
            PageMeta(id: pageID, title: "Doc", url: pageURL, frontmatter: pf.frontmatter),
            pageCollectionID: collection.id, pageSetID: set.id)
        let originalBytes = try Data(contentsOf: pageURL)

        let loadedSet = try #require(setManager.pageSets(in: source).first)
        try await setManager.moveSet(
            loadedSet, to: dest, destinationPageCollection: collection, sourcePageCollection: collection,
            contentManager: contentManager)

        // Folder relocated on disk.
        let newFolder = dest.folderURL.appendingPathComponent("Drafts", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: set.folderURL.path))
        #expect(FileManager.default.fileExists(atPath: newFolder.path))

        // Sidecar carries the same identity, re-pointed at the destination.
        let sidecar = try PageSet.load(
            from: newFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        #expect(sidecar.id == set.id)
        #expect(sidecar.parentID == dest.id)

        // Strip-free: the moved Page is byte-identical at the new path.
        let movedURL = NexusPaths.pageFileURL(forTitle: "Doc", in: newFolder)
        #expect(try Data(contentsOf: movedURL) == originalBytes)

        // Hoist ids before the dbQueue closures (@Sendable).
        let setID = set.id
        let destID = dest.id
        let collectionID = collection.id
        let movedPageID = pageID

        // Index: Set row re-pointed; Page row re-pointed with page_set_id intact.
        let setRow = try await index.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM page_sets WHERE id = ?", arguments: [setID])
        }
        #expect(setRow?["parent_set_id"] as String? == destID)
        let pageRow = try await index.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [movedPageID])
        }
        #expect(pageRow?["page_collection_id"] as String? == collectionID)
        #expect(pageRow?["page_set_id"] as String? == setID)

        // Caches: out of the source bucket, into the destination with the new
        // URL; the Set's Page bucket re-points at the moved file.
        #expect(setManager.pageSets(in: source).isEmpty)
        #expect(setManager.pageSets(in: dest).map(\.id) == [setID])
        #expect(setManager.pageSets(in: dest).first?.folderURL.path == newFolder.path)
        #expect(contentManager.pages(in: sidecar).map(\.url.path) == [movedURL.path])
    }

    // MARK: - Destination collision

    @Test("moveSet throws on destination title collision before any disk change")
    func destinationCollisionThrowsPreMove() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let collection = try makePageCollection(nexus: nexus, title: "Notes")
        let source = try makePageCollection(nexus: nexus, title: "Inbox", in: collection)
        let dest = try makePageCollection(nexus: nexus, title: "Archive", in: collection)
        let set = try makePageSet(title: "Drafts", in: source)
        _ = try writePage(titled: "Doc", in: set.folderURL)
        // The destination already holds a same-titled Set.
        _ = try makePageSet(title: "Drafts", in: dest)

        let contentManager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        let setManager = PageSetManager(nexus: nexus)
        await setManager.loadAll(types: [collection])

        let loadedSet = try #require(setManager.pageSets(in: source).first)
        await #expect(throws: PageSetValidator.ValidationError.duplicateTitle) {
            try await setManager.moveSet(
                loadedSet, to: dest, destinationPageCollection: collection, sourcePageCollection: collection,
                contentManager: contentManager)
        }

        // Source folder + Page untouched; caches unchanged on both sides.
        #expect(FileManager.default.fileExists(atPath: set.folderURL.path))
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Doc", in: set.folderURL).path))
        #expect(setManager.pageSets(in: source).count == 1)
        #expect(setManager.pageSets(in: dest).count == 1)
    }

    // MARK: - Cross-collection move (with strip)

    @Test("Cross-vault moveSet strips per-page values absent from the destination schema; moveStripTotal matches")
    func crossCollectionMoveStrips() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(index)

        // "Status" exists only on CollectionA; "Priority" exists on both BY NAME
        // (different ids), so its values survive the move.
        let onlyA = PropertyDefinition(id: "prop_only_a", name: "Status", type: .status)
        let sharedA = PropertyDefinition(id: "prop_shared_a", name: "Priority", type: .select)
        let sharedB = PropertyDefinition(id: "prop_shared_b", name: "Priority", type: .select)
        let collectionA = try makePageCollection(
            nexus: nexus, title: "CollectionA", properties: [onlyA, sharedA], index: index)
        let collectionB = try makePageCollection(
            nexus: nexus, title: "CollectionB", properties: [sharedB], index: index)
        let collA = try makePageCollection(nexus: nexus, title: "CollA", in: collectionA, index: index)
        let collB = try makePageCollection(nexus: nexus, title: "CollB", in: collectionB, index: index)
        let set = try makePageSet(title: "Drafts", in: collA, index: index)

        // Two Pages carry the doomed value (one alongside the keeper); a
        // third carries nothing strippable — total = 2.
        let strippedPageID = try writePage(
            titled: "One", in: set.folderURL,
            properties: ["prop_only_a": .status("done"), "prop_shared_a": .select("high")])
        _ = try writePage(
            titled: "Two", in: set.folderURL, properties: ["prop_only_a": .status("open")])
        _ = try writePage(titled: "Three", in: set.folderURL)

        let contentManager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        contentManager.indexUpdater = updater
        let setManager = PageSetManager(nexus: nexus)
        setManager.indexUpdater = updater
        await setManager.loadAll(types: [collectionA, collectionB])

        let loadedSet = try #require(setManager.pageSets(in: collA).first)
        let total = try await setManager.moveStripTotal(for: loadedSet, from: collectionA, to: collectionB)
        #expect(total == 2)

        try await setManager.moveSet(
            loadedSet, to: collB, destinationPageCollection: collectionB, sourcePageCollection: collectionA,
            contentManager: contentManager)

        // Stripped on disk; the name-shared value survived.
        let newFolder = collB.folderURL.appendingPathComponent("Drafts", isDirectory: true)
        let one = try PageFile.load(from: NexusPaths.pageFileURL(forTitle: "One", in: newFolder))
        #expect(one.frontmatter.properties["prop_only_a"] == nil)
        #expect(one.frontmatter.properties["prop_shared_a"] == .select("high"))
        let two = try PageFile.load(from: NexusPaths.pageFileURL(forTitle: "Two", in: newFolder))
        #expect(two.frontmatter.properties["prop_only_a"] == nil)

        // Hoist ids before the dbQueue closure (@Sendable).
        let collectionBID = collectionB.id
        let collBID = collB.id
        let setID = set.id
        let movedPageID = strippedPageID

        // Page rows re-indexed under the destination Collection/Collection/Set.
        let row = try await index.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [movedPageID])
        }
        #expect(row?["page_collection_id"] as String? == collectionBID)
        #expect(row?["page_set_id"] as String? == setID)
    }

    @Test("Cross-vault moveSet with no schema gap reports zero and moves byte-identical")
    func crossCollectionZeroStripMovesClean() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Same property NAME on both collections — nothing to strip.
        let propA = PropertyDefinition(id: "prop_a", name: "Priority", type: .select)
        let propB = PropertyDefinition(id: "prop_b", name: "Priority", type: .select)
        let collectionA = try makePageCollection(nexus: nexus, title: "CollectionA", properties: [propA])
        let collectionB = try makePageCollection(nexus: nexus, title: "CollectionB", properties: [propB])
        let collA = try makePageCollection(nexus: nexus, title: "CollA", in: collectionA)
        let collB = try makePageCollection(nexus: nexus, title: "CollB", in: collectionB)
        let set = try makePageSet(title: "Drafts", in: collA)
        _ = try writePage(
            titled: "Doc", in: set.folderURL, properties: ["prop_a": .select("high")])
        let originalBytes = try Data(
            contentsOf: NexusPaths.pageFileURL(forTitle: "Doc", in: set.folderURL))

        let contentManager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        let setManager = PageSetManager(nexus: nexus)
        await setManager.loadAll(types: [collectionA, collectionB])

        let loadedSet = try #require(setManager.pageSets(in: collA).first)
        let total = try await setManager.moveStripTotal(for: loadedSet, from: collectionA, to: collectionB)
        #expect(total == 0)

        try await setManager.moveSet(
            loadedSet, to: collB, destinationPageCollection: collectionB, sourcePageCollection: collectionA,
            contentManager: contentManager)

        let newFolder = collB.folderURL.appendingPathComponent("Drafts", isDirectory: true)
        let movedURL = NexusPaths.pageFileURL(forTitle: "Doc", in: newFolder)
        #expect(try Data(contentsOf: movedURL) == originalBytes)
        #expect(setManager.pageSets(in: collA).isEmpty)
        #expect(setManager.pageSets(in: collB).map(\.id) == [set.id])
    }

    // MARK: - Fixtures (mirror PageSetContentTests)

    @discardableResult
    private func makePageCollection(
        nexus: Nexus,
        title: String,
        properties: [PropertyDefinition] = [],
        index: PommoraIndex? = nil
    ) throws -> PageCollection {
        let collection = PageCollection(
            id: ULID.generate(), title: title, icon: nil,
            properties: properties, views: [], modifiedAt: Date()
        )
        let folderURL = NexusPaths.collectionFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try collection.save(to: NexusPaths.collectionMetadataURL(forTitle: title, in: nexus))
        if let index { try IndexUpdater(index).upsertPageCollection(collection) }
        return collection
    }

    @discardableResult
    private func makePageCollection(
        nexus: Nexus,
        title: String,
        in pageCollection: PageCollection,
        index: PommoraIndex? = nil
    ) throws -> PageSet {
        let folderURL = NexusPaths.setFolderURL(
            forTitle: title, inCollectionTitled: pageCollection.title, in: nexus
        )
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let coll = PageSet(
            id: ULID.generate(), parentID: pageCollection.id, title: title,
            folderURL: folderURL, modifiedAt: Date()
        )
        try coll.save(to: folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        if let index { try IndexUpdater(index).upsertPageCollection(coll) }
        return coll
    }

    @discardableResult
    private func makePageSet(
        title: String,
        in collection: PageSet,
        index: PommoraIndex? = nil
    ) throws -> PageSet {
        let folderURL = collection.folderURL.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let set = PageSet(
            id: ULID.generate(), parentID: collection.id, title: title,
            folderURL: folderURL, modifiedAt: Date()
        )
        try set.save(to: folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        if let index { try IndexUpdater(index).upsertPageSet(set) }
        return set
    }

    /// Writes a `.md` Page with proper frontmatter into `folder`; returns its id.
    @discardableResult
    private func writePage(
        titled title: String, in folder: URL, properties: [String: PropertyValue] = [:]
    ) throws -> String {
        let id = ULID.generate()
        let fm = PageFrontmatter(
            id: id, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: properties, createdAt: Date()
        )
        try AtomicYAMLMarkdown.write(
            frontmatter: fm, body: "",
            to: NexusPaths.pageFileURL(forTitle: title, in: folder))
        return id
    }
}
