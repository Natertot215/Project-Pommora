import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderItemTypes/Collections

/// Items-side mirror of PageTypeManager (ParadigmV2 — Task 5.3; flatlayout — Task 2.3).
///
/// Owns the in-memory view of every ItemType + its child ItemCollections
/// inside the active Nexus. Loads from `<nexus>/<TypeFolder>/_itemtype.json`
/// and per-collection `<...>/<CollectionFolder>/_itemcollection.json` sidecars.
/// Title-validation lives in `ItemTypeValidator` + `ItemCollectionValidator`.
///
/// flatlayout: ItemTypes sit at the Nexus root (no wrapper segment).
/// Discovery filters root folders by presence of `_itemtype.json`; folders
/// carrying any of the other per-kind sidecars (Pages/Agenda/Collection) or
/// no recognized sidecar are skipped. Items are brand-new data with no legacy
/// on disk, so the PageTypeManager-style `_vault.json`/`_collection.json`
/// migration is intentionally omitted.
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

    /// Injected by NexusManager in Phase E.7. Nil until wired; CRUD methods
    /// call it post-commit as a best-effort non-fatal write (filesystem is canonical).
    var indexUpdater: IndexUpdater?

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func itemCollections(in itemType: ItemType) -> [ItemCollection] {
        itemCollectionsByType[itemType.id] ?? []
    }

    /// Resolve the parent ItemType for a given ItemCollection via the
    /// ItemCollection's `typeID` field. Used by the sidebar to keep the
    /// parent Type leaf visually selected while the user is drilled into
    /// one of its Sets (which never renders as a sidebar row itself).
    func parentItemType(for collection: ItemCollection) -> ItemType? {
        typesByID[collection.typeID]
    }

    // MARK: - Load

    func loadAll() async {
        do {
            // flatlayout: ItemType folders sit at the Nexus root. Discovery
            // filters folders by presence of `_itemtype.json`; folders carrying
            // any of the other per-kind sidecars (Pages/Agenda/Collection) or
            // no recognized sidecar are skipped. NexusAdopter handles surfacing
            // unrecognized folders for adoption (Phase 4).
            let root = nexus.rootURL

            let topLevel = try Filesystem.childFolders(of: root)
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .filter { !$0.lastPathComponent.hasPrefix("_") }

            var loadedTypes: [ItemType] = []
            var loadedCols: [String: [ItemCollection]] = [:]

            for folder in topLevel {
                let metaURL = folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
                guard Filesystem.fileExists(at: metaURL),
                    var itemType = try? ItemType.load(from: metaURL)
                else { continue }

                // Default-view migration (Task 5, Phase A — v0.3.1). Mirrors
                // PageTypeManager.loadAll's pass. Idempotent (`views.isEmpty`
                // is the only mutation trigger); best-effort save (failures
                // re-try on next load).
                if itemType.views.isEmpty {
                    itemType.views = [
                        SavedView.defaultTable(visiblePropertyIDs: itemType.properties.map(\.id))
                    ]
                    try? itemType.save(to: metaURL)
                }
                loadedTypes.append(itemType)

                // Discover ItemCollections (sub-folders with `_itemcollection.json`;
                // skip _- and .-prefixed). A sub-folder inside an already-flat ItemType
                // can only be an ItemCollection, so if the sidecar is missing (folder
                // created by hand in Finder, or pre-existing before adoption), write
                // a fresh one in place. Best-effort: a write failure falls through
                // to the existing nil-skip behavior.
                let parentPropertyIDs = itemType.properties.map(\.id)
                let cols = try Filesystem.childFolders(of: folder)
                    .filter { !$0.lastPathComponent.hasPrefix("_") }
                    .filter { !$0.lastPathComponent.hasPrefix(".") }
                    .compactMap { sub -> ItemCollection? in
                        let collMetaURL = sub.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename)
                        if !Filesystem.fileExists(at: collMetaURL) {
                            let fresh = ItemCollection(
                                id: ULID.generate(),
                                typeID: itemType.id,
                                title: sub.lastPathComponent,
                                folderURL: sub,
                                modifiedAt: Date()
                            )
                            try? Filesystem.writeMetadataIntoExistingFolder(
                                metadataURL: collMetaURL, metadata: fresh
                            )
                        }
                        guard var collection = try? ItemCollection.load(from: collMetaURL) else {
                            return nil
                        }
                        // Default-view migration on the Collection. Each
                        // Collection is INDEPENDENT (locked decision) — its
                        // own default Table seeded with the parent ItemType's
                        // visible-property ordering as the starting set.
                        if collection.views.isEmpty {
                            collection.views = [
                                SavedView.defaultTable(visiblePropertyIDs: parentPropertyIDs)
                            ]
                            try? collection.save(to: collMetaURL)
                        }
                        return collection
                    }
                loadedCols[itemType.id] = OrderResolver.resolve(
                    cols,
                    persistedOrder: itemType.collectionOrder,
                    titleKeyPath: \ItemCollection.title
                )
            }

            self.types = OrderResolver.resolve(
                loadedTypes,
                persistedOrder: readPersistedItemTypeOrder(),
                titleKeyPath: \ItemType.title
            )
            self.itemCollectionsByType = loadedCols
            self.typesByID = Dictionary(uniqueKeysWithValues: self.types.map { ($0.id, $0) })
            self.pendingError = nil

            // Defensive index sync — mirrors PageTypeManager.loadAll's
            // post-load upsert pass. See that file for the full rationale.
            // tl;dr: entities arriving outside CRUD (adoption / external
            // folder creation) aren't in the DB; subsequent createItem /
            // updateItem call sites FK-fail. INSERT OR REPLACE makes this
            // idempotent; index is regeneratable so failures are swallowed.
            if let updater = indexUpdater {
                for itemType in self.types {
                    try? updater.upsertItemType(itemType)
                    for collection in self.itemCollectionsByType[itemType.id] ?? [] {
                        try? updater.upsertItemCollection(collection)
                    }
                }
            }
        } catch {
            self.types = []
            self.itemCollectionsByType = [:]
            self.typesByID = [:]
            self.pendingError = error
        }
    }

    // MARK: - ItemType CRUD

    @discardableResult
    func createItemType(name: String, icon: String?) async throws -> ItemType {
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
            // flatlayout: ItemType folders live directly at the Nexus root;
            // no wrapper to ensure.
            try Filesystem.createFolderWithMetadata(
                folderURL: folder, metadataURL: meta, metadata: itemType
            )

            if let updater = indexUpdater {
                do { try updater.upsertItemType(itemType) } catch { self.pendingError = error }
            }

            types.append(itemType)
            itemCollectionsByType[itemType.id] = []
            types = OrderResolver.resolve(
                types,
                persistedOrder: readPersistedItemTypeOrder(),
                titleKeyPath: \ItemType.title
            )
            rebuildTypesByID()
            return itemType
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

            if let updater = indexUpdater {
                do { try updater.upsertItemType(updated) } catch { self.pendingError = error }
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
                    persistedOrder: readPersistedItemTypeOrder(),
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
            if let updater = indexUpdater {
                do { try updater.upsertItemType(updated) } catch { self.pendingError = error }
            }
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
            if let updater = indexUpdater {
                do { try updater.deleteItemType(id: itemType.id) } catch { self.pendingError = error }
            }
            types.removeAll { $0.id == itemType.id }
            itemCollectionsByType.removeValue(forKey: itemType.id)
            typesByID.removeValue(forKey: itemType.id)
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - ItemCollection CRUD

    @discardableResult
    func createItemCollection(name: String, inItemType itemType: ItemType) async throws -> ItemCollection {
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

            if let updater = indexUpdater {
                do { try updater.upsertItemCollection(coll) } catch { self.pendingError = error }
            }

            var arr = existing
            arr.append(coll)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: itemType.collectionOrder,
                titleKeyPath: \ItemCollection.title
            )
            itemCollectionsByType[itemType.id] = arr
            return coll
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
            let metaURL = newURL.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename)
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

            if let updater = indexUpdater {
                do { try updater.upsertItemCollection(updated) } catch { self.pendingError = error }
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
            if let updater = indexUpdater {
                do { try updater.deleteItemCollection(id: collection.id) } catch { self.pendingError = error }
            }
            var arr = itemCollectionsByType[collection.typeID] ?? []
            arr.removeAll { $0.id == collection.id }
            itemCollectionsByType[collection.typeID] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Reorder

    /// Reorders Item Types in response to a sidebar drag. Matches the SwiftUI
    /// `.onMove(perform:)` signature. New full ID order persists to
    /// `.nexus/state.json`.
    func reorderItemTypes(fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = types
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != types else { return }
        types = arr
        rebuildTypesByID()
        do {
            try OrderPersister.setItemTypeOrder(arr.map(\.id), in: nexus)
        } catch {
            self.pendingError = error
        }
    }

    /// Reorders ItemCollections within `itemType`. New ID order persists to the
    /// parent Item Type's schema sidecar.
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
        do {
            try OrderPersister.setItemCollectionOrder(arr.map(\.id), in: itemType, nexus: nexus)
            // Keep the in-memory ItemType's collectionOrder in sync.
            if let i = types.firstIndex(where: { $0.id == itemType.id }) {
                types[i].collectionOrder = arr.map(\.id)
                rebuildTypesByID()
            }
        } catch {
            self.pendingError = error
        }
    }

    // MARK: - Private helpers

    private func rebuildTypesByID() {
        typesByID = Dictionary(uniqueKeysWithValues: types.map { ($0.id, $0) })
    }

    /// Reads the persisted Item Type sibling order from `.nexus/state.json`.
    /// Returns nil when there's no state file or no `item_type_order` recorded —
    /// the resolver falls back to alphabetic in that case.
    private func readPersistedItemTypeOrder() -> [String]? {
        let url = NexusPaths.nexusStateURL(in: nexus)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (try? AtomicJSON.decode(NexusState.self, from: url))?.itemTypeOrder
    }
}

// MARK: - Schema CRUD errors

enum ItemTypeManagerError: Error, Equatable {
    case typeNotFound
    case propertyNotFound
    case lossyChangeRequiresConfirmation
    case indexOutOfBounds
}

// MARK: - Schema CRUD methods

extension ItemTypeManager {

    // MARK: - Add property

    /// Adds a property definition to an Item Type's schema. If `definition.id` is empty,
    /// a new user-property ID (`prop_<ulid>`) is minted. Validates against existing
    /// properties via `PropertyDefinitionValidator`. Schema-only write (member files
    /// are not touched — identity is stored by ID).
    ///
    /// **Paired relations** (`definition.type == .relation && definition.dualProperty != nil`):
    /// Routed through `DualRelationCoordinator.createPairedRelation` which writes both
    /// Type sidecars atomically. Target must be another ItemType in this manager
    /// (`dualProperty.syncedPropertyDefinedOnTypeID`). Cross-side pairing (ItemType →
    /// PageType) is a post-v1 Prospect.
    func addProperty(_ definition: PropertyDefinition, to typeID: String) async throws {
        do {
            guard let i = types.firstIndex(where: { $0.id == typeID }) else {
                throw ItemTypeManagerError.typeNotFound
            }

            var def = definition
            if def.id.isEmpty {
                def.id = ReservedPropertyID.mintUserPropertyID()
            }

            // Paired relation: route through DualRelationCoordinator.
            if def.type == .relation, let dualConfig = def.dualProperty {
                let targetTypeID = dualConfig.syncedPropertyDefinedOnTypeID
                guard let scope = def.relationScope else {
                    throw ItemTypeManagerError.propertyNotFound
                }
                guard let targetType = types.first(where: { $0.id == targetTypeID }) else {
                    throw ItemTypeManagerError.typeNotFound
                }
                let sourceKind = DualRelationCoordinator.TypeKind.itemType(types[i])
                let targetKind = DualRelationCoordinator.TypeKind.itemType(targetType)
                let targetScope = PropertyDefinition.RelationScope.itemType(types[i].id)
                let reverseName = dualConfig.syncedPropertyID.isEmpty ? def.name : dualConfig.syncedPropertyID

                let (srcID, _) = try DualRelationCoordinator.createPairedRelation(
                    source: sourceKind,
                    sourcePropertyName: def.name,
                    sourceScope: scope,
                    target: targetKind,
                    targetPropertyName: reverseName,
                    targetScope: targetScope,
                    nexus: nexus
                )
                // Reload source type from disk.
                let meta = NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: types[i].title)
                if let reloaded = try? ItemType.load(from: meta) {
                    types[i] = reloaded
                    rebuildTypesByID()
                }
                // Reload target type if different.
                if targetTypeID != typeID, let j = types.firstIndex(where: { $0.id == targetTypeID }) {
                    let tMeta = NexusPaths.itemTypeMetadataURL(
                        in: nexus.rootURL, typeFolderName: targetType.title)
                    if let reloaded = try? ItemType.load(from: tMeta) {
                        types[j] = reloaded
                        rebuildTypesByID()
                    }
                }
                if let updater = indexUpdater {
                    if let addedDef = types[i].properties.first(where: { $0.id == srcID }) {
                        let position = types[i].properties.count - 1
                        do {
                            try updater.upsertPropertyDefinition(
                                addedDef, owningTypeID: typeID, owningTypeKind: "item_type",
                                position: position
                            )
                        } catch { self.pendingError = error }
                    }
                }
                return
            }

            try PropertyDefinitionValidator.validate(def, in: types[i].properties)

            var updated = types[i]
            updated.properties.append(def)
            updated.modifiedAt = Date()

            let meta = NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: updated.title)
            try updated.save(to: meta)

            if let updater = indexUpdater {
                let position = updated.properties.count - 1
                do { try updater.upsertPropertyDefinition(def, owningTypeID: typeID, owningTypeKind: "item_type", position: position) } catch { self.pendingError = error }
            }

            types[i] = updated
            rebuildTypesByID()
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Rename property

    /// Renames a property by its stable ID. Schema-only write — member files keyed by
    /// `id` are not touched (rename-safe by design per the domain model).
    func renameProperty(id propertyID: String, in typeID: String, to newName: String) async throws {
        do {
            guard let typeIndex = types.firstIndex(where: { $0.id == typeID }) else {
                throw ItemTypeManagerError.typeNotFound
            }
            guard let propIndex = types[typeIndex].properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw ItemTypeManagerError.propertyNotFound
            }

            var renamedDef = types[typeIndex].properties[propIndex]
            renamedDef.name = newName

            // Build the schema with the renamed definition substituted in, so validation
            // can check name-uniqueness against the rest of the schema (excluding itself).
            var otherProps = types[typeIndex].properties
            otherProps.remove(at: propIndex)
            // Validate name only — borrow the validator but supply a def with a fresh
            // temp-unique ID so the duplicate-ID rule doesn't fire. We only care about
            // the name-uniqueness check here.
            var validationDef = renamedDef
            validationDef.id = ReservedPropertyID.mintUserPropertyID()
            try PropertyDefinitionValidator.validate(validationDef, in: otherProps)

            var updated = types[typeIndex]
            updated.properties[propIndex] = renamedDef
            updated.modifiedAt = Date()

            let meta = NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: updated.title)
            try updated.save(to: meta)

            if let updater = indexUpdater {
                do { try updater.upsertPropertyDefinition(renamedDef, owningTypeID: typeID, owningTypeKind: "item_type", position: propIndex) } catch { self.pendingError = error }
            }

            types[typeIndex] = updated
            rebuildTypesByID()
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Delete property

    /// Deletes a property from the schema. Atomically removes the schema entry and
    /// strips the corresponding key from every member Item's `properties` dictionary
    /// via `SchemaTransaction`.
    ///
    /// **Paired relations** (`property.dualProperty != nil`): routed through
    /// `DualRelationCoordinator.deletePair` which cascades the delete to both
    /// Type sidecars and strips all values from member files on each side.
    // MARK: - Update view (per-container SavedView edit)

    /// Mirror of PageTypeManager.updateView — see that file for the rationale.
    /// containerID may be an ItemType.id or ItemCollection.id; we search both.
    func updateView(
        _ viewID: String,
        in containerID: String,
        transform: (inout SavedView) -> Void
    ) async throws {
        do {
            if let i = types.firstIndex(where: { $0.id == containerID }) {
                guard let vi = types[i].views.firstIndex(where: { $0.id == viewID }) else {
                    throw ItemTypeManagerError.propertyNotFound
                }
                var updated = types[i]
                transform(&updated.views[vi])
                updated.modifiedAt = Date()
                let meta = NexusPaths.itemTypeMetadataURL(
                    in: nexus.rootURL, typeFolderName: updated.title
                )
                try updated.save(to: meta)
                types[i] = updated
                typesByID[updated.id] = updated
                return
            }
            for (typeID, cols) in itemCollectionsByType {
                if let ci = cols.firstIndex(where: { $0.id == containerID }) {
                    var coll = cols[ci]
                    guard let vi = coll.views.firstIndex(where: { $0.id == viewID }) else {
                        throw ItemTypeManagerError.propertyNotFound
                    }
                    transform(&coll.views[vi])
                    coll.modifiedAt = Date()
                    let meta = coll.folderURL.appendingPathComponent(
                        NexusPaths.itemCollectionSidecarFilename
                    )
                    try coll.save(to: meta)
                    itemCollectionsByType[typeID]?[ci] = coll
                    return
                }
            }
            throw ItemTypeManagerError.typeNotFound
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Duplicate property

    /// Mirror of PageTypeManager.duplicateProperty. Deep-copies a property,
    /// mints a new ULID, appends "(copy)" to name, persists, indexes.
    /// Member Item files unaffected.
    func duplicateProperty(id propertyID: String, in typeID: String) async throws {
        do {
            guard let i = types.firstIndex(where: { $0.id == typeID }) else {
                throw ItemTypeManagerError.typeNotFound
            }
            guard let j = types[i].properties.firstIndex(where: { $0.id == propertyID }) else {
                throw ItemTypeManagerError.propertyNotFound
            }

            var duplicated = types[i].properties[j]
            duplicated.id = ReservedPropertyID.mintUserPropertyID()
            duplicated.name = "\(duplicated.name) (copy)"
            duplicated.dualProperty = nil  // Defer relation dup re-pairing to v0.3.1.5.

            try PropertyDefinitionValidator.validate(duplicated, in: types[i].properties)

            var updatedType = types[i]
            updatedType.properties.append(duplicated)
            updatedType.modifiedAt = Date()

            let meta = NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: updatedType.title)
            try updatedType.save(to: meta)

            if let updater = indexUpdater {
                let position = updatedType.properties.count - 1
                do {
                    try updater.upsertPropertyDefinition(
                        duplicated, owningTypeID: typeID, owningTypeKind: "item_type", position: position
                    )
                } catch { self.pendingError = error }
            }

            types[i] = updatedType
            typesByID[typeID] = updatedType
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Update property (transform-based per-config edit)

    /// Apply an in-place transform to a PropertyDefinition's per-config
    /// fields. Mirrors PageTypeManager.updateProperty — see that file for
    /// the full rationale. Used by EditPropertyPane (Task 11).
    func updateProperty(
        id propertyID: String,
        in typeID: String,
        transform: (inout PropertyDefinition) -> Void
    ) async throws {
        do {
            guard let i = types.firstIndex(where: { $0.id == typeID }) else {
                throw ItemTypeManagerError.typeNotFound
            }
            guard let j = types[i].properties.firstIndex(where: { $0.id == propertyID }) else {
                throw ItemTypeManagerError.propertyNotFound
            }

            var updatedDef = types[i].properties[j]
            transform(&updatedDef)

            var siblings = types[i].properties
            siblings.remove(at: j)
            try PropertyDefinitionValidator.validate(updatedDef, in: siblings)

            var updatedType = types[i]
            updatedType.properties[j] = updatedDef
            updatedType.modifiedAt = Date()

            let meta = NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: updatedType.title)
            try updatedType.save(to: meta)

            if let updater = indexUpdater {
                do {
                    try updater.upsertPropertyDefinition(
                        updatedDef, owningTypeID: typeID, owningTypeKind: "item_type", position: j
                    )
                } catch { self.pendingError = error }
            }

            types[i] = updatedType
            typesByID[typeID] = updatedType
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func deleteProperty(id propertyID: String, in typeID: String) async throws {
        do {
            guard let typeIndex = types.firstIndex(where: { $0.id == typeID }) else {
                throw ItemTypeManagerError.typeNotFound
            }
            guard let propIndex = types[typeIndex].properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw ItemTypeManagerError.propertyNotFound
            }

            let prop = types[typeIndex].properties[propIndex]

            // Paired relation: route through DualRelationCoordinator (cascades both sides).
            if prop.type == .relation, let dualConfig = prop.dualProperty {
                let targetTypeID = dualConfig.syncedPropertyDefinedOnTypeID
                let ownerKind = DualRelationCoordinator.TypeKind.itemType(types[typeIndex])
                if let targetType = types.first(where: { $0.id == targetTypeID }) {
                    let reverseKind = DualRelationCoordinator.TypeKind.itemType(targetType)
                    try DualRelationCoordinator.deletePair(
                        propertyID: propertyID,
                        owner: ownerKind,
                        reverse: reverseKind,
                        nexus: nexus
                    )
                    // Reload both types in-memory.
                    let meta = NexusPaths.itemTypeMetadataURL(
                        in: nexus.rootURL, typeFolderName: types[typeIndex].title)
                    if let reloaded = try? ItemType.load(from: meta) {
                        types[typeIndex] = reloaded
                        rebuildTypesByID()
                    }
                    if let j = types.firstIndex(where: { $0.id == targetTypeID }) {
                        let tMeta = NexusPaths.itemTypeMetadataURL(
                            in: nexus.rootURL, typeFolderName: targetType.title)
                        if let reloaded = try? ItemType.load(from: tMeta) {
                            types[j] = reloaded
                            rebuildTypesByID()
                        }
                    }
                    if let updater = indexUpdater {
                        do { try updater.deletePropertyDefinition(id: propertyID) } catch { self.pendingError = error }
                        do { try updater.deletePropertyDefinition(id: dualConfig.syncedPropertyID) } catch { self.pendingError = error }
                    }
                    return
                }
                // Target not found in-memory: fall through to simple delete of source only.
                _ = ownerKind
            }

            var updated = types[typeIndex]
            updated.properties.remove(at: propIndex)
            updated.modifiedAt = Date()

            let tx = SchemaTransaction()

            // Stage updated schema sidecar.
            let meta = NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: updated.title)
            try tx.stage(updated, to: meta)

            // Stage member-file rewrites: strip the property key from every Item's properties dict.
            let typeFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: updated.title)
            let itemFiles = try Filesystem.descendantFiles(
                of: typeFolder,
                where: { url in
                    url.pathExtension == "json" && !url.lastPathComponent.hasPrefix("_")
                })
            for itemURL in itemFiles {
                var item = try AtomicJSON.decode(Item.self, from: itemURL)
                guard item.properties[propertyID] != nil else { continue }
                item.properties.removeValue(forKey: propertyID)
                tx.stage(payload: try AtomicJSON.encode(item), to: itemURL)
            }

            try tx.commit()

            if let updater = indexUpdater {
                do { try updater.deletePropertyDefinition(id: propertyID) } catch { self.pendingError = error }
            }

            types[typeIndex] = updated
            rebuildTypesByID()
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Reorder property

    /// Moves a property to a new index within the schema's `properties` array.
    /// Schema-only write — member files are not touched.
    func reorderProperty(id propertyID: String, in typeID: String, toIndex newIndex: Int) async throws {
        do {
            guard let typeIndex = types.firstIndex(where: { $0.id == typeID }) else {
                throw ItemTypeManagerError.typeNotFound
            }
            guard let propIndex = types[typeIndex].properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw ItemTypeManagerError.propertyNotFound
            }

            var props = types[typeIndex].properties
            let clampedIndex = min(max(newIndex, 0), props.count - 1)
            guard clampedIndex != propIndex else { return }

            guard clampedIndex >= 0 && clampedIndex < props.count else {
                throw ItemTypeManagerError.indexOutOfBounds
            }

            props.move(
                fromOffsets: IndexSet(integer: propIndex),
                toOffset: clampedIndex > propIndex ? clampedIndex + 1 : clampedIndex)

            var updated = types[typeIndex]
            updated.properties = props
            updated.modifiedAt = Date()

            let meta = NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: updated.title)
            try updated.save(to: meta)

            if let updater = indexUpdater {
                for (pos, def) in updated.properties.enumerated() {
                    do { try updater.upsertPropertyDefinition(def, owningTypeID: typeID, owningTypeKind: "item_type", position: pos) } catch { self.pendingError = error }
                }
            }

            types[typeIndex] = updated
            rebuildTypesByID()
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Change property type

    /// Changes the type of an existing property.
    ///
    /// **Lossless path** (`oldType == newType`): updates the schema sidecar only.
    ///
    /// **Lossy path** (`oldType != newType`):
    /// - `dropConflictingValues == false` → throws `.lossyChangeRequiresConfirmation`
    ///   so the caller can surface a confirmation dialog.
    /// - `dropConflictingValues == true` → atomically updates the schema sidecar and
    ///   strips the property's value from every member Item's properties dict via
    ///   `SchemaTransaction`.
    func changeType(
        of propertyID: String,
        in typeID: String,
        to newType: PropertyType,
        dropConflictingValues: Bool = false
    ) async throws {
        do {
            guard let typeIndex = types.firstIndex(where: { $0.id == typeID }) else {
                throw ItemTypeManagerError.typeNotFound
            }
            guard let propIndex = types[typeIndex].properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw ItemTypeManagerError.propertyNotFound
            }

            let oldType = types[typeIndex].properties[propIndex].type

            if oldType == newType {
                // Lossless: schema-only write to bump modifiedAt.
                var updated = types[typeIndex]
                updated.properties[propIndex].type = newType
                updated.modifiedAt = Date()
                let meta = NexusPaths.itemTypeMetadataURL(
                    in: nexus.rootURL, typeFolderName: updated.title)
                try updated.save(to: meta)
                if let updater = indexUpdater {
                    let def = updated.properties[propIndex]
                    do { try updater.upsertPropertyDefinition(def, owningTypeID: typeID, owningTypeKind: "item_type", position: propIndex) } catch { self.pendingError = error }
                }
                types[typeIndex] = updated
                rebuildTypesByID()
                return
            }

            // Lossy cross-type change.
            guard dropConflictingValues else {
                throw ItemTypeManagerError.lossyChangeRequiresConfirmation
            }

            var updated = types[typeIndex]
            updated.properties[propIndex].type = newType
            updated.modifiedAt = Date()

            let tx = SchemaTransaction()

            // Stage updated schema sidecar.
            let meta = NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: updated.title)
            try tx.stage(updated, to: meta)

            // Stage member-file rewrites: strip the conflicting property value from
            // every Item's properties dict so no stale cross-type value lingers.
            let typeFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: updated.title)
            let itemFiles = try Filesystem.descendantFiles(
                of: typeFolder,
                where: { url in
                    url.pathExtension == "json" && !url.lastPathComponent.hasPrefix("_")
                })
            for itemURL in itemFiles {
                var item = try AtomicJSON.decode(Item.self, from: itemURL)
                guard item.properties[propertyID] != nil else { continue }
                item.properties.removeValue(forKey: propertyID)
                tx.stage(payload: try AtomicJSON.encode(item), to: itemURL)
            }

            try tx.commit()

            if let updater = indexUpdater {
                let def = updated.properties[propIndex]
                do { try updater.upsertPropertyDefinition(def, owningTypeID: typeID, owningTypeKind: "item_type", position: propIndex) } catch { self.pendingError = error }
            }

            types[typeIndex] = updated
            rebuildTypesByID()
        } catch {
            self.pendingError = error
            throw error
        }
    }
}
