import Foundation
import Testing

@testable import Pommora

/// Items-side mirror of PageContentManagerTests + PageContentManagerTypeRootTests
/// (ParadigmV2 — Task 5.6). Covers both ItemCollection-scoped and
/// Item-Type-root CRUD paths.
@MainActor
@Suite("ItemContentManager")
struct ItemContentManagerTests {

    // MARK: - ItemCollection-scoped

    @Test("createItem writes .md inside ItemCollection")
    func createItem() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        let created = try await manager.createItem(name: "Buy milk", in: coll, type: itemType)
        let url = NexusPaths.itemFileURL(forTitle: "Buy milk", in: coll.folderURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let items = manager.items(in: coll)
        #expect(items.count == 1)
        #expect(items.first?.title == "Buy milk")
        #expect(items.first?.id == created.id)

        let loaded = try Item.load(from: url)
        #expect(!loaded.id.isEmpty)
        #expect(loaded.title == "Buy milk")
        #expect(loaded.properties.isEmpty)
    }

    @Test("createItem rejects duplicate title (case-insensitive) in same ItemCollection")
    func duplicateTitleRejected() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        _ = try await manager.createItem(name: "Buy milk", in: coll, type: itemType)
        await #expect(throws: ItemCRUDError.duplicateTitle) {
            _ = try await manager.createItem(name: "buy MILK", in: coll, type: itemType)
        }
        #expect(manager.items(in: coll).count == 1)
    }

    @Test("createItem rejects empty + invalid-character titles")
    func emptyAndInvalidTitleRejected() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        await #expect(throws: ItemCRUDError.emptyTitle) {
            _ = try await manager.createItem(name: "   ", in: coll, type: itemType)
        }
        await #expect(throws: ItemCRUDError.invalidTitleCharacters) {
            _ = try await manager.createItem(name: "bad/title", in: coll, type: itemType)
        }
    }

    @Test("renameItem moves file + updates items list")
    func renameItem() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }
        _ = try await manager.createItem(name: "Buy milk", in: coll, type: itemType)
        let item = manager.items(in: coll).first!

        try await manager.renameItem(item, to: "Buy bread", in: coll, type: itemType)
        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.itemFileURL(forTitle: "Buy milk", in: coll.folderURL).path
            ))
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.itemFileURL(forTitle: "Buy bread", in: coll.folderURL).path
            ))
        #expect(manager.items(in: coll).first?.title == "Buy bread")
    }

    @Test("renameItem succeeds on a drifted Item (>1000-char body) — title-only validation")
    func renameDriftedItemSucceeds() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }

        // Create a normal Item, then simulate migration / loadLenient surfacing a
        // legacy Item whose body exceeds the 1000-char cap (preserved verbatim).
        let created = try await manager.createItem(name: "Recipe", in: coll, type: itemType)
        let drifted = Item(
            id: created.id, title: "Recipe", icon: created.icon,
            description: String(repeating: "x", count: ItemValidator.maxDescriptionLength + 500),
            tier1: [], tier2: [], tier3: [], properties: [:],
            createdAt: created.createdAt, modifiedAt: created.modifiedAt)
        // Persist the drift to disk so the rename's preserving write round-trips it.
        let oldURL = NexusPaths.itemFileURL(forTitle: "Recipe", in: coll.folderURL)
        try drifted.save(to: oldURL)

        // A pure TITLE rename must NOT throw on the untouched over-cap body —
        // whole-item validation (which would throw .descriptionTooLong) is scoped
        // out of rename. Before SHOULD-FIX 5 this threw.
        try await manager.renameItem(drifted, to: "Recipe (renamed)", in: coll, type: itemType)

        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.itemFileURL(forTitle: "Recipe", in: coll.folderURL).path))
        let newURL = NexusPaths.itemFileURL(forTitle: "Recipe (renamed)", in: coll.folderURL)
        #expect(FileManager.default.fileExists(atPath: newURL.path))
        // The over-cap body survived the rename verbatim (never truncated / rejected).
        let reloaded = try Item.load(from: newURL)
        #expect(reloaded.description.count == ItemValidator.maxDescriptionLength + 500)
    }

    @Test("deleteItem removes file (in ItemCollection)")
    func deleteItem() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }
        _ = try await manager.createItem(name: "Buy milk", in: coll, type: itemType)
        let item = manager.items(in: coll).first!
        let url = NexusPaths.itemFileURL(forTitle: "Buy milk", in: coll.folderURL)

        try await manager.deleteItem(item, in: coll)

        #expect(manager.items(in: coll).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        // File now in .trash, preserving relative path under nexus root
        // (flatlayout: Item file lives at <nexus>/<Type>/<Collection>/).
        let trashFile = NexusPaths.trashDir(in: nexus)
            .appendingPathComponent("T/C/Buy milk.md")
        #expect(FileManager.default.fileExists(atPath: trashFile.path))
    }

    @Test("loadAll discovers existing .md in an ItemCollection")
    func loadExisting() async throws {
        let (nexus, _, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }
        // Hoist ULID per branch quirk #5 (Sendable capture safety).
        let id = ULID.generate()
        let pre = Item(
            id: id, title: "Pre", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(), modifiedAt: Date()
        )
        try pre.save(to: NexusPaths.itemFileURL(forTitle: "Pre", in: coll.folderURL))

        await manager.loadAll(for: coll)
        #expect(manager.items(in: coll).count == 1)
        #expect(manager.items(in: coll).first?.id == id)
    }

    @Test("updateItem persists changes + preserves id")
    func updateItem() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }
        let created = try await manager.createItem(name: "Buy milk", in: coll, type: itemType)

        var updated = created
        updated.description = "Whole milk"
        try await manager.updateItem(updated, in: coll, type: itemType)

        let url = NexusPaths.itemFileURL(forTitle: "Buy milk", in: coll.folderURL)
        let reloaded = try Item.load(from: url)
        #expect(reloaded.description == "Whole milk")
        #expect(reloaded.id == created.id)
    }

    // MARK: - ItemType-root scoped

    @Test("loadAll for an empty type root yields empty arrays")
    func loadAllForTypeEmpty() async throws {
        let (nexus, itemType, manager) = try await setupTypeRoot()
        defer { TempNexus.cleanup(nexus) }

        await manager.loadAll(for: itemType)
        #expect(manager.items(in: itemType).isEmpty)
    }

    @Test("loadAll for a type with .md files at root populates itemsByTypeRoot")
    func loadAllForTypeWithItems() async throws {
        let (nexus, itemType, manager) = try await setupTypeRoot()
        defer { TempNexus.cleanup(nexus) }

        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: itemType.title)
        // Pin timestamps far apart so idA < idB is guaranteed (creation-order
        // sort is ULID-ascending; two rapid ULID.generate() calls share the same
        // millisecond timestamp and their random tails can collide in any order).
        let idA = ULID.generate(at: Date(timeIntervalSince1970: 1_000_000))
        let idB = ULID.generate(at: Date(timeIntervalSince1970: 2_000_000))
        try Item(
            id: idA, title: "Alpha", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(), modifiedAt: Date()
        ).save(to: NexusPaths.itemFileURL(forTitle: "Alpha", in: folder))
        try Item(
            id: idB, title: "Beta", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(), modifiedAt: Date()
        ).save(to: NexusPaths.itemFileURL(forTitle: "Beta", in: folder))

        await manager.loadAll(for: itemType)
        let titles = manager.items(in: itemType).map(\.title)
        #expect(titles.count == 2)
        // idA < idB (older timestamp) → Alpha sorts first under creation-order default.
        #expect(titles == ["Alpha", "Beta"])
    }

    @Test("loadAll for a type ignores ItemCollection sub-folder contents")
    func loadAllForTypeIgnoresCollectionContents() async throws {
        let (nexus, itemType, manager) = try await setupTypeRoot()
        defer { TempNexus.cleanup(nexus) }

        // One Item at type root
        let typeFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: itemType.title)
        let rootID = ULID.generate()
        try Item(
            id: rootID, title: "RootItem", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(), modifiedAt: Date()
        ).save(to: NexusPaths.itemFileURL(forTitle: "RootItem", in: typeFolder))

        // One ItemCollection sub-folder containing one Item
        let collFolder = NexusPaths.itemCollectionFolderURL(
            in: nexus.rootURL,
            typeFolderName: itemType.title,
            collectionFolderName: "Inner"
        )
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = ItemCollection(
            id: ULID.generate(),
            typeID: itemType.id,
            title: "Inner",
            folderURL: collFolder,
            modifiedAt: Date()
        )
        // Sidecar so type-root walk recognizes Inner as an ItemCollection + skips it
        try coll.save(to: collFolder.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename))
        let innerID = ULID.generate()
        try Item(
            id: innerID, title: "InnerItem", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(), modifiedAt: Date()
        ).save(to: NexusPaths.itemFileURL(forTitle: "InnerItem", in: collFolder))

        await manager.loadAll(for: itemType)
        await manager.loadAll(for: coll)

        let rootItems = manager.items(in: itemType)
        let collItems = manager.items(in: coll)
        #expect(rootItems.count == 1)
        #expect(rootItems.first?.title == "RootItem")
        #expect(collItems.count == 1)
        #expect(collItems.first?.title == "InnerItem")
    }

    @Test("createItem in type root writes .md + updates items(in: itemType)")
    func createItemInTypeRoot() async throws {
        let (nexus, itemType, manager) = try await setupTypeRoot()
        defer { TempNexus.cleanup(nexus) }

        _ = try await manager.createItem(name: "Notes", inTypeRoot: itemType)
        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: itemType.title)
        let url = NexusPaths.itemFileURL(forTitle: "Notes", in: folder)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let items = manager.items(in: itemType)
        #expect(items.count == 1)
        #expect(items.first?.title == "Notes")

        let loaded = try Item.load(from: url)
        #expect(!loaded.id.isEmpty)
    }

    @Test("renameItem in type root moves file + updates items(in: itemType)")
    func renameItemInTypeRoot() async throws {
        let (nexus, itemType, manager) = try await setupTypeRoot()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: itemType.title)
        _ = try await manager.createItem(name: "Notes", inTypeRoot: itemType)
        let item = manager.items(in: itemType).first!

        try await manager.renameItem(item, to: "Ideas", inTypeRoot: itemType)
        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.itemFileURL(forTitle: "Notes", in: folder).path
            ))
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.itemFileURL(forTitle: "Ideas", in: folder).path
            ))
        #expect(manager.items(in: itemType).first?.title == "Ideas")
    }

    @Test("createItem in type root rejects duplicate title (case-insensitive)")
    func duplicateTitleRejectedInTypeRoot() async throws {
        let (nexus, itemType, manager) = try await setupTypeRoot()
        defer { TempNexus.cleanup(nexus) }

        _ = try await manager.createItem(name: "Notes", inTypeRoot: itemType)
        await #expect(throws: ItemCRUDError.duplicateTitle) {
            _ = try await manager.createItem(name: "NOTES", inTypeRoot: itemType)
        }
        #expect(manager.items(in: itemType).count == 1)
    }

    @Test("deleteItem in type root removes file + updates items(in: itemType)")
    func deleteItemInTypeRoot() async throws {
        let (nexus, itemType, manager) = try await setupTypeRoot()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: itemType.title)
        _ = try await manager.createItem(name: "Notes", inTypeRoot: itemType)
        let item = manager.items(in: itemType).first!

        try await manager.deleteItem(item, inTypeRoot: itemType)
        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.itemFileURL(forTitle: "Notes", in: folder).path
            ))
        #expect(manager.items(in: itemType).isEmpty)
    }

    // MARK: - Single-property value writes

    @Test("updateItemProperty with .null removes the key (does not persist a literal null)")
    func nullValueRemovesKeyNotPersistsNull() async throws {
        let (nexus, itemType, manager) = try await TempNexus.itemTypeRoot(named: "T")
        defer { TempNexus.cleanup(nexus) }

        let created = try await manager.createItem(name: "I", inTypeRoot: itemType)
        try await manager.updateItemProperty(
            created, propertyID: "p", newValue: .select("x"), type: itemType, collection: nil)
        try await manager.updateItemProperty(
            created, propertyID: "p", newValue: .null, type: itemType, collection: nil)

        let fresh = TempNexus.reopen(nexus)
        await fresh.loadAll(for: itemType)
        #expect(fresh.items(in: itemType).first?.properties["p"] == nil)
    }

    // MARK: - Icon edit vs body-cap (A3)

    @Test("updateItemIcon on an already-over-cap Item does not throw + persists the icon")
    func updateItemIconSkipsBodyCapOnOverCapItem() async throws {
        let (nexus, itemType, manager) = try await setupTypeRoot()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: itemType.title)

        // Create normally (empty body passes createItem), then OVERWRITE the .md
        // on disk with a body exceeding the effective cap (default 500). Mirrors
        // the drift-simulation pattern in `renameDriftedItemSucceeds`: a verbatim
        // `Item.save` envelope write the loader round-trips faithfully.
        let created = try await manager.createItem(name: "Notes", inTypeRoot: itemType)
        let url = NexusPaths.itemFileURL(forTitle: "Notes", in: folder)
        let overCap = Item(
            id: created.id, title: "Notes", icon: created.icon,
            description: String(repeating: "x", count: ItemValidator.maxDescriptionLength + 100),
            tier1: [], tier2: [], tier3: [], properties: [:],
            createdAt: created.createdAt, modifiedAt: created.modifiedAt)
        try overCap.save(to: url)

        // Reload so the manager holds the over-cap Item (its in-memory copy is
        // still the empty-body create otherwise).
        await manager.loadAll(for: itemType)
        let reloaded = manager.items(in: itemType).first!
        #expect(reloaded.description.count == ItemValidator.maxDescriptionLength + 100)

        // An icon edit must NOT re-run the body-cap on the untouched over-cap
        // body. Before A3 this threw `.descriptionTooLong` (updateItemIcon →
        // updateItem → validate → cap check).
        await #expect(throws: Never.self) {
            try await manager.updateItemIcon(reloaded, to: "star", type: itemType, collection: nil)
        }

        // The icon persisted; the over-cap body survived verbatim.
        let fresh = TempNexus.reopen(nexus)
        await fresh.loadAll(for: itemType)
        let final = fresh.items(in: itemType).first!
        #expect(final.icon == "star")
        #expect(final.description.count == ItemValidator.maxDescriptionLength + 100)
    }

    // MARK: - Setup

    /// Bootstraps a temp nexus with an ItemType + ItemCollection materialized
    /// directly at the Nexus root (flatlayout), then returns a fresh manager.
    private func setupCollection() async throws -> (Nexus, ItemType, ItemCollection, ItemContentManager) {
        let nexus = try TempNexus.make()
        let itemType = ItemType(
            id: ULID.generate(), title: "T", icon: nil,
            properties: [], views: [], modifiedAt: Date())

        // Materialize <nexus>/T/ + per-kind sidecar
        let typeFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "T")
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try itemType.save(to: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "T"))

        // Materialize <nexus>/T/C/ + per-kind sidecar
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

    /// Type-root variant: materializes only the ItemType folder (no Collection).
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
