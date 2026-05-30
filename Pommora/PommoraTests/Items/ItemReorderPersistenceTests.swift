import Foundation
import Testing

@testable import Pommora

/// RED — verifies that `ItemContentManager.reorderItems` persists the new
/// item order to the on-disk sidecar. Both stubs currently do the in-memory
/// move only; neither writes to disk, so both assertions fail until the
/// OrderPersister wiring lands (GREEN step).
@MainActor
@Suite("ItemReorderPersistenceTests")
struct ItemReorderPersistenceTests {

    // MARK: - Case 1: ItemCollection-scoped reorder persists to _itemcollection.json

    @Test("reorderItems(in:) persists new id order to _itemcollection.json sidecar")
    func reorderItemsInCollectionPersistsSidecar() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        // Create two items via the real CRUD path so both the .json files and
        // the sidecar exist on disk in a known state.
        let itemA = try await manager.createItem(name: "Alpha", in: coll, type: itemType)
        let itemB = try await manager.createItem(name: "Beta", in: coll, type: itemType)

        // Sanity: in-memory order is [Alpha, Beta] (creation order).
        let before = manager.items(in: coll)
        #expect(before.map(\.id) == [itemA.id, itemB.id])

        // Move last item (index 1 = Beta) to front (offset 0).
        manager.reorderItems(in: coll, fromOffsets: IndexSet(integer: 1), toOffset: 0)

        // In-memory reflects the move immediately.
        let afterMemory = manager.items(in: coll)
        #expect(afterMemory.map(\.id) == [itemB.id, itemA.id])

        // Reload sidecar from disk — must reflect the persisted order.
        let sidecarURL = coll.folderURL
            .appendingPathComponent(NexusPaths.itemCollectionSidecarFilename)
        let reloaded = try ItemCollection.load(from: sidecarURL)

        // RED: currently nil because the persister is not wired; expected [Beta.id, Alpha.id].
        #expect(reloaded.itemOrder == [itemB.id, itemA.id])
    }

    // MARK: - Case 2: ItemType-root reorder persists to _itemtype.json

    @Test("reorderItems(inType:) persists new id order to _itemtype.json sidecar")
    func reorderItemsInTypeRootPersistsSidecar() async throws {
        let (nexus, itemType, manager) = try await setupTypeRoot()
        defer { TempNexus.cleanup(nexus) }

        // Create two items at the type root via the real CRUD path.
        let itemA = try await manager.createItem(name: "Alpha", inTypeRoot: itemType)
        let itemB = try await manager.createItem(name: "Beta", inTypeRoot: itemType)

        // Sanity: in-memory order is [Alpha, Beta] (creation order).
        let before = manager.items(in: itemType)
        #expect(before.map(\.id) == [itemA.id, itemB.id])

        // Move last item (index 1 = Beta) to front (offset 0).
        manager.reorderItems(inType: itemType, fromOffsets: IndexSet(integer: 1), toOffset: 0)

        // In-memory reflects the move immediately.
        let afterMemory = manager.items(in: itemType)
        #expect(afterMemory.map(\.id) == [itemB.id, itemA.id])

        // Reload sidecar from disk — must reflect the persisted order.
        let sidecarURL = NexusPaths.itemTypeMetadataURL(
            in: nexus.rootURL, typeFolderName: itemType.title
        )
        let reloaded = try ItemType.load(from: sidecarURL)

        // RED: currently nil because the persister is not wired; expected [Beta.id, Alpha.id].
        #expect(reloaded.itemOrder == [itemB.id, itemA.id])
    }

    // MARK: - Setup (mirrored from ItemContentManagerTests)

    /// Bootstraps a temp nexus with an ItemType + ItemCollection materialized on
    /// disk, then returns a fresh manager.
    private func setupCollection() async throws -> (Nexus, ItemType, ItemCollection, ItemContentManager) {
        let nexus = try TempNexus.make()
        let itemType = ItemType(
            id: ULID.generate(), title: "T", icon: nil,
            properties: [], views: [], modifiedAt: Date())

        let typeFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "T")
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try itemType.save(to: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "T"))

        let collFolder = NexusPaths.itemCollectionFolderURL(
            in: nexus.rootURL, typeFolderName: "T", collectionFolderName: "C"
        )
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = ItemCollection(
            id: ULID.generate(),
            typeID: itemType.id,
            title: "C",
            folderURL: collFolder,
            modifiedAt: Date()
        )
        try coll.save(to: collFolder.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename))

        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, itemType, coll, manager)
    }

    /// Type-root variant: materializes only the ItemType folder (no collection).
    private func setupTypeRoot() async throws -> (Nexus, ItemType, ItemContentManager) {
        let nexus = try TempNexus.make()
        let itemType = ItemType(
            id: ULID.generate(), title: "T", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        let typeFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "T")
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try itemType.save(to: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "T"))

        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, itemType, manager)
    }
}
