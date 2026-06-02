import Foundation
import GRDB
import Testing

@testable import Pommora

/// `.md`-only Item behavior (Task 10b retired the transitional `.json`/`.md`
/// dual-format code). A `.md` Item survives updateItem / deleteItem / renameItem
/// with NO orphan and NO double, loadAll lists exactly one row per id, and new
/// Items always write `.md`. The `.json` → `.md` conversion itself is covered by
/// `ItemFormatMigrationTests`; the same-launch index visibility of a freshly
/// converted Item is covered here (launch-ordering guarantee).
@MainActor
@Suite("ItemMarkdownTransition")
struct ItemMarkdownTransitionTests {

    // MARK: - .md Item survival (no orphan / no double)

    @Test("a .md Item is visible via loadAll")
    func markdownVisible() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        try Self.writeMarkdown(
            title: "Note", id: "01HMD", in: coll.folderURL, description: "md body")

        await manager.loadAll(for: coll)
        let items = manager.items(in: coll)
        #expect(items.count == 1)
        #expect(items.first?.id == "01HMD")
        #expect(items.first?.title == "Note")
        #expect(items.first?.description == "md body")
    }

    @Test("updateItem on a .md Item rewrites the .md in place — no orphan, no double")
    func updateMarkdownNoOrphan() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        try Self.writeMarkdown(
            title: "Note", id: "01HMD", in: coll.folderURL, description: "body")
        await manager.loadAll(for: coll)
        var item = manager.items(in: coll).first!

        item.description = "edited body"
        try await manager.updateItem(item, in: coll, type: itemType)

        // The `.md` still exists and was updated; NO stray `.json`.
        let mdURL = NexusPaths.itemFileURL(forTitle: "Note", in: coll.folderURL)
        let jsonURL = coll.folderURL.appendingPathComponent("Note.json")
        #expect(FileManager.default.fileExists(atPath: mdURL.path))
        #expect(!FileManager.default.fileExists(atPath: jsonURL.path))
        #expect(try Item.load(from: mdURL).description == "edited body")

        await manager.loadAll(for: coll)
        #expect(manager.items(in: coll).count == 1)
    }

    @Test("renameItem on a .md Item renames .md → .md — no orphan, no double")
    func renameMarkdownNoOrphan() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        try Self.writeMarkdown(
            title: "OldNote", id: "01HMD", in: coll.folderURL, description: "body")
        await manager.loadAll(for: coll)
        let item = manager.items(in: coll).first!

        try await manager.renameItem(item, to: "NewNote", in: coll, type: itemType)

        let oldMD = NexusPaths.itemFileURL(forTitle: "OldNote", in: coll.folderURL)
        let newMD = NexusPaths.itemFileURL(forTitle: "NewNote", in: coll.folderURL)
        #expect(!FileManager.default.fileExists(atPath: oldMD.path))
        #expect(FileManager.default.fileExists(atPath: newMD.path))

        await manager.loadAll(for: coll)
        #expect(manager.items(in: coll).count == 1)
        #expect(manager.items(in: coll).first?.title == "NewNote")
    }

    @Test("deleteItem on a .md Item trashes the .md")
    func deleteMarkdown() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        try Self.writeMarkdown(
            title: "Note", id: "01HMD", in: coll.folderURL, description: "body")
        await manager.loadAll(for: coll)
        let item = manager.items(in: coll).first!

        try await manager.deleteItem(item, in: coll)

        let mdURL = NexusPaths.itemFileURL(forTitle: "Note", in: coll.folderURL)
        #expect(!FileManager.default.fileExists(atPath: mdURL.path))
        #expect(manager.items(in: coll).isEmpty)

        await manager.loadAll(for: coll)
        #expect(manager.items(in: coll).isEmpty)
    }

    @Test("loadAll de-dups two .md files sharing an id (external-Finder edge)")
    func dedupByID() async throws {
        let (nexus, _, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        // Two distinct `.md` files holding the SAME id (only reachable via external
        // Finder manipulation). loadAll collapses them to one row.
        try Self.writeMarkdown(
            title: "TwinA", id: "01HTWIN", in: coll.folderURL, description: "a")
        try Self.writeMarkdown(
            title: "TwinB", id: "01HTWIN", in: coll.folderURL, description: "b")

        await manager.loadAll(for: coll)
        #expect(manager.items(in: coll).count == 1)
    }

    // MARK: - New Items always write .md

    @Test("createItem always writes .md (canonical format)")
    func createWritesMarkdown() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        _ = try await manager.createItem(name: "Fresh", in: coll, type: itemType)
        let mdURL = NexusPaths.itemFileURL(forTitle: "Fresh", in: coll.folderURL)
        let jsonURL = coll.folderURL.appendingPathComponent("Fresh.json")
        #expect(FileManager.default.fileExists(atPath: mdURL.path))
        #expect(!FileManager.default.fileExists(atPath: jsonURL.path))
        let raw = try String(contentsOf: mdURL, encoding: .utf8)
        #expect(raw.contains("Class: item"))
    }

    // MARK: - Indexing visibility (data-layer confirmation)

    @Test("a .md Item is indexed by IndexBuilder")
    func markdownIndexed() async throws {
        let (nexus, _, coll, _) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        try Self.writeMarkdown(
            title: "ColMD", id: "01HCOLMD", in: coll.folderURL, description: "x")

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus)

        let count = try await idx.dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM items WHERE id = '01HCOLMD'") ?? -1
        }
        #expect(count == 1)
    }

    // MARK: - Launch ordering: migration → index (same-launch visibility)

    /// The #1 correctness guarantee of Task 10b. The index reads `.md`-only, so a
    /// legacy `.json` Item that was never indexed (e.g. dropped into a Finder
    /// folder after the last rebuild) must be converted to `.md` AND indexed on
    /// the SAME launch. The launch sequence runs `ItemFormatMigration` before
    /// `openIndex`, and `openIndex(forceRebuild:)` repopulates when the migration
    /// converted anything. This test exercises that ordering on a current-version
    /// index (so `needsRebuild == false` — only `forceRebuild` makes it visible).
    @Test("a freshly migrated .md Item is in the index on the same launch")
    func migratedItemIndexedSameLaunch() async throws {
        let (nexus, _, coll, _) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        // 1. Open + stamp a current-version index that does NOT contain the Item.
        let (idx, needsRebuild) = try PommoraIndex.open(at: nexus.rootURL)
        if needsRebuild {
            try await IndexBuilder.populate(index: idx, from: nexus)
        }
        try idx.markSchemaVersionCurrent()
        let beforeMigration = try await idx.dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM items WHERE id = '01HJSONLATE'") ?? -1
        }
        #expect(beforeMigration == 0)

        // 2. A legacy `.json` Item appears (as if dropped in via Finder).
        try Self.writeLegacyJSON(
            title: "LateArrival", id: "01HJSONLATE", in: coll.folderURL,
            description: "arrived after last rebuild")

        // 3. The format migration converts it to `.md` (the launch hook's work).
        let report = ItemFormatMigration.runIfNeeded(at: nexus.rootURL)
        #expect(report.itemsConverted == 1)
        #expect(report.didAnyWork)

        // 4. A second open returns the SAME current-version index (needsRebuild
        //    == false). Without forceRebuild, the converted `.md` would be absent.
        let (idx2, needsRebuild2) = try PommoraIndex.open(at: nexus.rootURL)
        #expect(!needsRebuild2)

        // forceRebuild (driven by report.didAnyWork) repopulates the index from the
        // freshly-converted `.md` on this same launch.
        try await IndexBuilder.populate(index: idx2, from: nexus)
        let afterRebuild = try await idx2.dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM items WHERE id = '01HJSONLATE'") ?? -1
        }
        #expect(afterRebuild == 1)
    }

    // MARK: - Helpers

    /// Writes a canonical `.md` Item via the production `Item.save` path.
    private static func writeMarkdown(
        title: String, id: String, in folder: URL, description: String
    ) throws {
        let item = Item(
            id: id, title: title, icon: nil, description: description,
            tier1: [], tier2: [], tier3: [], properties: [:],
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            modifiedAt: Date(timeIntervalSince1970: 2_000_000))
        try item.save(to: NexusPaths.itemFileURL(forTitle: title, in: folder))
    }

    /// Writes a genuine legacy `.json` Item (pre-conversion on-disk shape) into
    /// `folder` — used to seed the format migration. Title = filename stem.
    private static func writeLegacyJSON(
        title: String, id: String, in folder: URL, description: String
    ) throws {
        let item = Item(
            id: id, title: title, icon: nil, description: description,
            tier1: [], tier2: [], tier3: [], properties: [:],
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            modifiedAt: Date(timeIntervalSince1970: 2_000_000))
        let url = folder.appendingPathComponent("\(title).json")
        try AtomicJSON.write(item, to: url)
    }

    private func setupCollection() async throws -> (Nexus, ItemType, ItemCollection, ItemContentManager) {
        let nexus = try TempNexus.make()
        let itemType = ItemType(
            id: ULID.generate(), title: "T", icon: nil,
            properties: [], views: [], modifiedAt: Date())

        let typeFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "T")
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try itemType.save(to: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "T"))

        let collFolder = NexusPaths.itemCollectionFolderURL(
            in: nexus.rootURL, typeFolderName: "T", collectionFolderName: "C")
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = ItemCollection(
            id: ULID.generate(), typeID: itemType.id, title: "C",
            folderURL: collFolder, modifiedAt: Date())
        try coll.save(to: collFolder.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename))

        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, itemType, coll, manager)
    }
}
