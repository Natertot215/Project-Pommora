import Foundation
import Testing

@testable import Pommora

/// Items-side mirror of PageTypeManagerTests (flatlayout — Task 2.3).
///
/// flatlayout: ItemType folders live directly at the Nexus root; discovery
/// filters by `_itemtype.json` sidecar presence.
@MainActor
@Suite("ItemTypeManager")
struct ItemTypeManagerTests {

    @Test("loadAll on a fresh nexus yields empty + no wrapper created")
    func loadAllEmptyOnFreshNexus() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)

        await manager.loadAll()
        #expect(manager.types.isEmpty)
        #expect(manager.itemCollectionsByType.isEmpty)
        #expect(manager.pendingError == nil)

        // flatlayout: no `Items/` wrapper is materialized — type folders sit
        // at the Nexus root and the loader walks root directly.
        let wrapper = nexus.rootURL.appendingPathComponent("Items", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: wrapper.path))
    }

    @Test("createItemType writes folder + _itemtype.json at the Nexus root")
    func createItemType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Errands", icon: "cart")
        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "Errands")
        let meta = NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "Errands")
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: meta.path))
        #expect(meta.lastPathComponent == NexusPaths.itemTypeSidecarFilename)
        // flatlayout: no `Items/` wrapper is created as a side effect of the
        // first ItemType.
        let wrapper = nexus.rootURL.appendingPathComponent("Items", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: wrapper.path))
        #expect(manager.types.count == 1)
        #expect(manager.types.first?.title == "Errands")
        #expect(manager.typesByID[manager.types.first!.id]?.title == "Errands")
    }

    @Test("createItemCollection creates folder inside ItemType")
    func createItemCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Errands", icon: nil)
        let itemType = manager.types.first!
        try await manager.createItemCollection(name: "Groceries", inItemType: itemType)

        let folder = NexusPaths.itemCollectionFolderURL(
            in: nexus.rootURL,
            typeFolderName: "Errands",
            collectionFolderName: "Groceries"
        )
        #expect(FileManager.default.fileExists(atPath: folder.path))
        let cols = manager.itemCollections(in: itemType)
        #expect(cols.count == 1)
        #expect(cols.first?.title == "Groceries")
        #expect(cols.first?.typeID == itemType.id)
    }

    @Test("renameItemType renames folder + preserves child collections")
    func renameItemType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Errands", icon: nil)
        let itemType = manager.types.first!
        try await manager.createItemCollection(name: "Groceries", inItemType: itemType)

        try await manager.renameItemType(itemType, to: "Tasks")
        let newFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "Tasks")
        let oldFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "Errands")
        #expect(FileManager.default.fileExists(atPath: newFolder.path))
        #expect(!FileManager.default.fileExists(atPath: oldFolder.path))

        // ItemCollection still present under renamed ItemType
        let renamedType = manager.types.first!
        let cols = manager.itemCollections(in: renamedType)
        #expect(cols.count == 1)
        #expect(cols.first?.title == "Groceries")

        // ItemCollection folderURL rebuilt to live under the new parent path
        let expectedCollFolder = NexusPaths.itemCollectionFolderURL(
            in: nexus.rootURL,
            typeFolderName: "Tasks",
            collectionFolderName: "Groceries"
        )
        #expect(cols.first?.folderURL == expectedCollFolder)
    }

    @Test("deleteItemType removes folder + clears collections")
    func deleteItemType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Errands", icon: nil)
        let itemType = manager.types.first!
        try await manager.createItemCollection(name: "Groceries", inItemType: itemType)

        try await manager.deleteItemType(itemType)
        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "Errands")
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(manager.types.isEmpty)
        #expect(manager.typesByID[itemType.id] == nil)

        // Folder now in .trash, preserving relative path under nexus root
        // (flatlayout: ItemType folder lives directly at the nexus root).
        let trashFolder = NexusPaths.trashDir(in: nexus).appendingPathComponent("Errands")
        #expect(FileManager.default.fileExists(atPath: trashFolder.path))
    }

    @Test("renameItemCollection moves the folder + updates folderURL")
    func renameItemCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()
        try await manager.createItemType(name: "Errands", icon: nil)
        let itemType = manager.types.first!
        try await manager.createItemCollection(name: "Groceries", inItemType: itemType)
        let coll = manager.itemCollections(in: itemType).first!

        try await manager.renameItemCollection(coll, to: "Supplies")
        let newFolder = NexusPaths.itemCollectionFolderURL(
            in: nexus.rootURL,
            typeFolderName: "Errands",
            collectionFolderName: "Supplies"
        )
        let oldFolder = NexusPaths.itemCollectionFolderURL(
            in: nexus.rootURL,
            typeFolderName: "Errands",
            collectionFolderName: "Groceries"
        )
        #expect(FileManager.default.fileExists(atPath: newFolder.path))
        #expect(!FileManager.default.fileExists(atPath: oldFolder.path))
        let renamed = manager.itemCollections(in: itemType).first!
        #expect(renamed.title == "Supplies")
        #expect(renamed.folderURL == newFolder)
    }

    @Test("deleteItemCollection removes folder + clears in-memory entry")
    func deleteItemCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()
        try await manager.createItemType(name: "Errands", icon: nil)
        let itemType = manager.types.first!
        try await manager.createItemCollection(name: "Groceries", inItemType: itemType)
        let coll = manager.itemCollections(in: itemType).first!

        try await manager.deleteItemCollection(coll)
        let folder = NexusPaths.itemCollectionFolderURL(
            in: nexus.rootURL,
            typeFolderName: "Errands",
            collectionFolderName: "Groceries"
        )
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(manager.itemCollections(in: itemType).isEmpty)

        // Folder now in .trash, preserving relative path under nexus root
        // (flatlayout: ItemCollection folder lives inside <nexus>/<Type>/).
        let trashFolder = NexusPaths.trashDir(in: nexus)
            .appendingPathComponent("Errands/Groceries")
        #expect(FileManager.default.fileExists(atPath: trashFolder.path))
    }

    @Test("updateItemTypeIcon persists icon change + survives reload")
    func updateItemTypeIcon() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Errands", icon: nil)
        let itemType = manager.types.first!
        #expect(itemType.icon == nil)

        try await manager.updateItemTypeIcon(itemType, to: "cart.fill")
        #expect(manager.types.first?.icon == "cart.fill")
        #expect(manager.typesByID[itemType.id]?.icon == "cart.fill")

        // Reload from disk to confirm persistence
        let fresh = ItemTypeManager(nexus: nexus)
        await fresh.loadAll()
        #expect(fresh.types.first?.icon == "cart.fill")

        // Clearing back to nil also round-trips
        let reloaded = fresh.types.first!
        try await fresh.updateItemTypeIcon(reloaded, to: nil)
        #expect(fresh.types.first?.icon == nil)

        let fresh2 = ItemTypeManager(nexus: nexus)
        await fresh2.loadAll()
        #expect(fresh2.types.first?.icon == nil)
    }

    @Test("loadAll discovers existing ItemTypes at the Nexus root after createItemType")
    func loadAllAfterCreate() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)

        try await manager.createItemType(name: "Errands", icon: nil)
        let itemType = manager.types.first!
        try await manager.createItemCollection(name: "Groceries", inItemType: itemType)

        // Spin up a fresh manager + reload from disk
        let fresh = ItemTypeManager(nexus: nexus)
        await fresh.loadAll()
        #expect(fresh.types.count == 1)
        #expect(fresh.types.first?.title == "Errands")
        #expect(fresh.itemCollections(in: fresh.types.first!).count == 1)
        #expect(fresh.itemCollections(in: fresh.types.first!).first?.title == "Groceries")
    }
}
