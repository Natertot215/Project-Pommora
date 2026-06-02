import Foundation
import GRDB
import Testing

@testable import Pommora

/// Transition-window tests for the Items `.json` → `.md` conversion (Task 3).
/// A legacy `.json` Item must stay VISIBLE (loadAll lists it) and survive
/// updateItem / deleteItem / renameItem with NO orphan (`.json` left beside a
/// new `.md`) and NO double (both twins listed). loadAll de-dups by id
/// preferring the `.md` twin when both exist.
@MainActor
@Suite("ItemMarkdownTransition")
struct ItemMarkdownTransitionTests {

    // MARK: - Legacy .json visibility + survival

    @Test("a legacy .json Item is visible via loadAll (no blackout)")
    func legacyJSONVisible() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        try Self.writeLegacyJSON(
            title: "OldItem", id: "01HLEGACY", in: coll.folderURL,
            description: "legacy body")

        await manager.loadAll(for: coll)
        let items = manager.items(in: coll)
        #expect(items.count == 1)
        #expect(items.first?.id == "01HLEGACY")
        #expect(items.first?.title == "OldItem")
        #expect(items.first?.description == "legacy body")
    }

    @Test("updateItem on a legacy .json Item rewrites the .json in place — no orphan .md, no double")
    func updateLegacyNoOrphan() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        try Self.writeLegacyJSON(
            title: "OldItem", id: "01HLEGACY", in: coll.folderURL, description: "body")
        await manager.loadAll(for: coll)
        var item = manager.items(in: coll).first!

        item.description = "edited body"
        try await manager.updateItem(item, in: coll, type: itemType)

        // The legacy `.json` still exists and was updated; NO orphan `.md` twin.
        let jsonURL = coll.folderURL.appendingPathComponent("OldItem.json")
        let mdURL = NexusPaths.itemFileURL(forTitle: "OldItem", in: coll.folderURL)
        #expect(FileManager.default.fileExists(atPath: jsonURL.path))
        #expect(!FileManager.default.fileExists(atPath: mdURL.path))
        let reloaded = try Item.load(from: jsonURL)
        #expect(reloaded.description == "edited body")

        // No double: a fresh loadAll lists exactly one.
        await manager.loadAll(for: coll)
        #expect(manager.items(in: coll).count == 1)
    }

    @Test("renameItem on a legacy .json Item renames .json → .json — no orphan, no double")
    func renameLegacyNoOrphan() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        try Self.writeLegacyJSON(
            title: "OldItem", id: "01HLEGACY", in: coll.folderURL, description: "body")
        await manager.loadAll(for: coll)
        let item = manager.items(in: coll).first!

        try await manager.renameItem(item, to: "NewItem", in: coll, type: itemType)

        let oldJSON = coll.folderURL.appendingPathComponent("OldItem.json")
        let newJSON = coll.folderURL.appendingPathComponent("NewItem.json")
        let newMD = NexusPaths.itemFileURL(forTitle: "NewItem", in: coll.folderURL)
        #expect(!FileManager.default.fileExists(atPath: oldJSON.path))
        #expect(FileManager.default.fileExists(atPath: newJSON.path))  // stays .json
        #expect(!FileManager.default.fileExists(atPath: newMD.path))  // no orphan .md

        await manager.loadAll(for: coll)
        #expect(manager.items(in: coll).count == 1)
        #expect(manager.items(in: coll).first?.title == "NewItem")
    }

    @Test("deleteItem on a legacy .json Item trashes the .json (no phantom .md)")
    func deleteLegacy() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        try Self.writeLegacyJSON(
            title: "OldItem", id: "01HLEGACY", in: coll.folderURL, description: "body")
        await manager.loadAll(for: coll)
        let item = manager.items(in: coll).first!

        try await manager.deleteItem(item, in: coll)

        let jsonURL = coll.folderURL.appendingPathComponent("OldItem.json")
        #expect(!FileManager.default.fileExists(atPath: jsonURL.path))
        #expect(manager.items(in: coll).isEmpty)

        await manager.loadAll(for: coll)
        #expect(manager.items(in: coll).isEmpty)
    }

    @Test("loadAll de-dups a .json + .md twin, preferring the .md")
    func dedupPrefersMarkdown() async throws {
        let (nexus, _, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        // Same id, both formats present (a partially-migrated state).
        try Self.writeLegacyJSON(
            title: "Twin", id: "01HTWIN", in: coll.folderURL, description: "json body")
        let mdItem = Item(
            id: "01HTWIN", title: "Twin", icon: nil, description: "md body",
            tier1: [], tier2: [], tier3: [], properties: [:],
            createdAt: Date(), modifiedAt: Date())
        try mdItem.save(to: NexusPaths.itemFileURL(forTitle: "Twin", in: coll.folderURL))

        await manager.loadAll(for: coll)
        let items = manager.items(in: coll)
        // Exactly one (de-duped) and the `.md` won.
        #expect(items.count == 1)
        #expect(items.first?.description == "md body")
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

    @Test("a legacy .json Item is indexed by IndexBuilder (no de-index)")
    func legacyJSONIndexed() async throws {
        let (nexus, _, coll, _) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        try Self.writeLegacyJSON(
            title: "ColLegacy", id: "01HCOLLEG", in: coll.folderURL, description: "x")

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus)

        // The legacy Item resolved into the index (data-layer confirmation per L18).
        let count = try await idx.dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM items WHERE id = '01HCOLLEG'") ?? -1
        }
        #expect(count == 1)
    }

    // MARK: - Helpers

    /// Writes a genuine legacy `.json` Item (pre-conversion on-disk shape) into
    /// `folder`. Title = filename stem; the JSON omits the title field.
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
