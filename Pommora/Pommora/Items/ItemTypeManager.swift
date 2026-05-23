import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderItemTypes/Collections

/// Items-side mirror of PageTypeManager (ParadigmV2 — Task 5.3).
///
/// Owns the in-memory view of every ItemType + its child ItemCollections
/// inside the active Nexus. Loads from `<nexus>/Items/<TypeFolder>/_schema.json`
/// and per-collection `<...>/<CollectionFolder>/_schema.json` sidecars.
/// Title-validation lives in `ItemTypeValidator` + `ItemCollectionValidator`
/// (Task 5.4).
///
/// Pre-Phase-6 stub: ItemTypes/ItemCollections live under `<nexus>/Items/`,
/// but that wrapper isn't created on disk until Phase 6. Until then,
/// `loadAll()` returns empty — there's nothing to read yet. CRUD methods
/// are fully functional so Phase 6 can wire the wrapper-creation path in
/// without rewriting the manager (stub-and-progressively-replace per
/// branch quirk #8). Items are brand-new data with no legacy on disk, so
/// the PageTypeManager-style `_vault.json`/`_collection.json` migration
/// is intentionally omitted.
@MainActor
@Observable
final class ItemTypeManager {
    private(set) var types: [ItemType] = []
    private(set) var itemCollectionsByType: [String: [ItemCollection]] = [:]
    /// Fast id-keyed lookup. Rebuilt alongside `types` so callers never need
    /// to scan the array when they already hold an ItemType id (Items-side
    /// queries do this often).
    private(set) var typesByID: [String: ItemType] = [:]
    var pendingError: (any Error)?

    private let nexus: Nexus

    /// Current Nexus ID — used by the drag system's cross-window guard.
    var nexusID: String { nexus.id }

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func itemCollections(in itemType: ItemType) -> [ItemCollection] {
        itemCollectionsByType[itemType.id] ?? []
    }

    // MARK: - Load

    func loadAll() async {
        do {
            let wrapper = NexusPaths.itemsWrapperDir(in: nexus.rootURL)
            // Phase 6 materializes `<nexus>/Items/` on disk. Until then this
            // bails cleanly with an empty load (no error surfaced) — Task 5.3
            // ships the manager green standalone per branch quirk #8.
            guard FileManager.default.fileExists(atPath: wrapper.path) else {
                self.types = []
                self.itemCollectionsByType = [:]
                self.typesByID = [:]
                self.pendingError = nil
                return
            }

            let topLevel = try Filesystem.childFolders(of: wrapper)
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .filter { !$0.lastPathComponent.hasPrefix("_") }

            var loadedTypes: [ItemType] = []
            var loadedCols: [String: [ItemCollection]] = [:]

            for folder in topLevel {
                let metaURL = NexusPaths.itemTypeMetadataURL(
                    in: nexus.rootURL,
                    typeFolderName: folder.lastPathComponent
                )
                guard Filesystem.fileExists(at: metaURL),
                    let itemType = try? ItemType.load(from: metaURL)
                else { continue }
                loadedTypes.append(itemType)

                let cols = try Filesystem.childFolders(of: folder)
                    .filter { !$0.lastPathComponent.hasPrefix("_") }
                    .filter { !$0.lastPathComponent.hasPrefix(".") }
                    .compactMap { sub -> ItemCollection? in
                        let metaURL = sub.appendingPathComponent(NexusPaths.schemaSidecarFilename)
                        guard Filesystem.fileExists(at: metaURL) else { return nil }
                        return try? ItemCollection.load(from: metaURL)
                    }
                loadedCols[itemType.id] = OrderResolver.resolve(
                    cols,
                    persistedOrder: itemType.collectionOrder,
                    titleKeyPath: \ItemCollection.title
                )
            }

            // Sibling order persistence for ItemTypes lands with later phases;
            // for Task 5.3 we fall through to OrderResolver's alphabetic tail
            // (no persisted-order field on NexusState yet).
            self.types = OrderResolver.resolve(
                loadedTypes,
                persistedOrder: nil,
                titleKeyPath: \ItemType.title
            )
            self.itemCollectionsByType = loadedCols
            self.typesByID = Dictionary(uniqueKeysWithValues: self.types.map { ($0.id, $0) })
            self.pendingError = nil
        } catch {
            self.types = []
            self.itemCollectionsByType = [:]
            self.typesByID = [:]
            self.pendingError = error
        }
    }

    // MARK: - ItemType CRUD

    func createItemType(name: String, icon: String?) async throws {
        do {
            try ItemTypeValidator.validate(title: name, existing: types)

            let itemType = ItemType(
                id: ULID.generate(),
                title: name,
                icon: icon,
                properties: [],
                views: [],
                modifiedAt: Date()
            )
            let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: name)
            let meta = NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: name)
            // Ensure `<nexus>/Items/` exists. Phase 6 will own wrapper-creation
            // explicitly; this keeps CRUD functional in the meantime.
            try NexusPaths.ensureDirectoryExists(NexusPaths.itemsWrapperDir(in: nexus.rootURL))
            try Filesystem.createFolderWithMetadata(
                folderURL: folder, metadataURL: meta, metadata: itemType
            )

            types.append(itemType)
            itemCollectionsByType[itemType.id] = []
            types = OrderResolver.resolve(
                types,
                persistedOrder: nil,
                titleKeyPath: \ItemType.title
            )
            rebuildTypesByID()
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renameItemType(_ itemType: ItemType, to newName: String) async throws {
        do {
            try ItemTypeValidator.validate(title: newName, existing: types, excluding: itemType)

            let oldFolder = NexusPaths.itemTypeFolderURL(
                in: nexus.rootURL, typeFolderName: itemType.title
            )
            let newFolder = NexusPaths.itemTypeFolderURL(
                in: nexus.rootURL, typeFolderName: newName
            )
            try Filesystem.renameFolder(from: oldFolder, to: newFolder)

            var updated = itemType
            updated.title = newName
            updated.modifiedAt = Date()
            let newMeta = NexusPaths.itemTypeMetadataURL(
                in: nexus.rootURL, typeFolderName: newName
            )
            do {
                try updated.save(to: newMeta)
            } catch let saveError {
                // Roll back folder rename; do NOT touch itemCollectionsByType
                // here — in-memory rebuild only runs on the save-success
                // branch below.
                do {
                    try Filesystem.renameFolder(from: newFolder, to: oldFolder)
                    throw saveError
                } catch let revertError {
                    let combined = RenameAtomicityError(saveError: saveError, revertError: revertError)
                    self.pendingError = combined
                    throw combined
                }
            }

            if let i = types.firstIndex(where: { $0.id == itemType.id }) {
                types[i] = updated
                // Rebuild ItemCollection in-memory under new parent path
                // (id + type_id unchanged; schema sidecar moved with its
                // folder, just re-derive folderURL). Preserve itemOrder so
                // a rename doesn't drop persisted ordering.
                if let oldCols = itemCollectionsByType[itemType.id] {
                    let rebuilt = oldCols.map { c -> ItemCollection in
                        let newCollURL = newFolder.appendingPathComponent(c.title, isDirectory: true)
                        return ItemCollection(
                            id: c.id,
                            typeID: c.typeID,
                            title: c.title,
                            folderURL: newCollURL,
                            modifiedAt: c.modifiedAt,
                            itemOrder: c.itemOrder
                        )
                    }
                    itemCollectionsByType[itemType.id] = rebuilt
                }
                types = OrderResolver.resolve(
                    types,
                    persistedOrder: nil,
                    titleKeyPath: \ItemType.title
                )
                rebuildTypesByID()
            }
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func updateItemTypeIcon(_ itemType: ItemType, to icon: String?) async throws {
        do {
            var updated = itemType
            updated.icon = icon
            updated.modifiedAt = Date()
            let meta = NexusPaths.itemTypeMetadataURL(
                in: nexus.rootURL, typeFolderName: itemType.title
            )
            try updated.save(to: meta)
            if let i = types.firstIndex(where: { $0.id == itemType.id }) {
                types[i] = updated
                rebuildTypesByID()
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func deleteItemType(_ itemType: ItemType) async throws {
        do {
            let folder = NexusPaths.itemTypeFolderURL(
                in: nexus.rootURL, typeFolderName: itemType.title
            )
            try Filesystem.moveToTrash(folder, in: nexus)
            types.removeAll { $0.id == itemType.id }
            itemCollectionsByType.removeValue(forKey: itemType.id)
            typesByID.removeValue(forKey: itemType.id)
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - ItemCollection CRUD

    func createItemCollection(name: String, inItemType itemType: ItemType) async throws {
        do {
            let existing = itemCollectionsByType[itemType.id] ?? []
            try ItemCollectionValidator.validate(title: name, existingInType: existing)

            let folder = NexusPaths.itemCollectionFolderURL(
                in: nexus.rootURL,
                typeFolderName: itemType.title,
                collectionFolderName: name
            )
            let now = Date()
            let coll = ItemCollection(
                id: ULID.generate(),
                typeID: itemType.id,
                title: name,
                folderURL: folder,
                modifiedAt: now
            )
            let metaURL = NexusPaths.itemCollectionMetadataURL(
                in: nexus.rootURL,
                typeFolderName: itemType.title,
                collectionFolderName: name
            )
            try Filesystem.createFolderWithMetadata(
                folderURL: folder, metadataURL: metaURL, metadata: coll
            )

            var arr = existing
            arr.append(coll)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: itemType.collectionOrder,
                titleKeyPath: \ItemCollection.title
            )
            itemCollectionsByType[itemType.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renameItemCollection(_ collection: ItemCollection, to newName: String) async throws {
        do {
            guard let itemType = types.first(where: { $0.id == collection.typeID }) else { return }
            let existing = itemCollectionsByType[itemType.id] ?? []
            try ItemCollectionValidator.validate(
                title: newName, existingInType: existing, excluding: collection
            )

            let newURL = NexusPaths.itemCollectionFolderURL(
                in: nexus.rootURL,
                typeFolderName: itemType.title,
                collectionFolderName: newName
            )
            try Filesystem.renameFolder(from: collection.folderURL, to: newURL)

            let now = Date()
            let updated = ItemCollection(
                id: collection.id,
                typeID: collection.typeID,
                title: newName,
                folderURL: newURL,
                modifiedAt: now,
                itemOrder: collection.itemOrder
            )
            let metaURL = newURL.appendingPathComponent(NexusPaths.schemaSidecarFilename)
            do {
                try updated.save(to: metaURL)
            } catch let saveError {
                do {
                    try Filesystem.renameFolder(from: newURL, to: collection.folderURL)
                    throw saveError
                } catch let revertError {
                    let combined = RenameAtomicityError(saveError: saveError, revertError: revertError)
                    self.pendingError = combined
                    throw combined
                }
            }

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == collection.id }) {
                arr[i] = updated
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: itemType.collectionOrder,
                    titleKeyPath: \ItemCollection.title
                )
            }
            itemCollectionsByType[itemType.id] = arr
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func deleteItemCollection(_ collection: ItemCollection) async throws {
        do {
            try Filesystem.moveToTrash(collection.folderURL, in: nexus)
            var arr = itemCollectionsByType[collection.typeID] ?? []
            arr.removeAll { $0.id == collection.id }
            itemCollectionsByType[collection.typeID] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Reorder (in-memory only for Task 5.3)
    //
    // Top-level ItemType sibling order persistence + per-ItemType
    // collectionOrder persistence land in a later wave (NexusState gains
    // `itemTypeOrder`; OrderPersister gains `setItemTypeOrder` +
    // `setItemCollectionOrder`). For now these mutate in-memory only so
    // SwiftUI `.onMove(perform:)` wires through without crashing; the
    // alphabetic resolver is the source of truth on reload.

    func reorderItemTypes(fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = types
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != types else { return }
        types = arr
        rebuildTypesByID()
    }

    func reorderItemCollections(
        in itemType: ItemType,
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        var arr = itemCollectionsByType[itemType.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        itemCollectionsByType[itemType.id] = arr
    }

    // MARK: - Private helpers

    private func rebuildTypesByID() {
        typesByID = Dictionary(uniqueKeysWithValues: types.map { ($0.id, $0) })
    }
}
