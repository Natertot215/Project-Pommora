import Foundation

/// CRUD methods for Items across both ItemCollection-scoped and
/// Item-Type-root-scoped storage. Split out from `ItemContentManager.swift`
/// for legibility, mirroring `PageContentManager+CRUD.swift`.
///
/// **ParadigmV2 (Task 5.5 — stub-and-progressively-replace):**
/// - Property validation against the Item Type's schema lands in Phase 6
///   once `ItemValidator` is rewired off `PageType`. Until then, CRUD uses an
///   inline title-uniqueness check matching `PageContentManager`'s shape.
/// - Item-Type-root paths assume the `<nexus>/Items/<TypeFolder>/` wrapper
///   exists; NexusAdopter materializes the wrapper in Phase 6.
///
/// Every CRUD method:
/// - Wraps its body in `do { … } catch { self.pendingError = error; throw error }`
///   so the sidebar toast can surface failures.
/// - For rename methods that do two filesystem ops (rename + save), applies
///   the rename-atomicity rollback pattern; if the revert ALSO fails it
///   surfaces a `RenameAtomicityError`.
extension ItemContentManager {

    // MARK: - Title uniqueness (transitional)
    //
    // Used until Phase 6 wires a proper ItemValidator-vs-ItemType. Matches the
    // case-insensitive uniqueness rule that ItemValidator enforces today.
    fileprivate func enforceTitleUniqueness(
        _ trimmed: String,
        among siblings: [Item],
        excluding: Item? = nil
    ) throws {
        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard !trimmed.isEmpty else { throw ItemCRUDError.emptyTitle }
        guard trimmed.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ItemCRUDError.invalidTitleCharacters
        }
        let conflict = siblings.contains { i in
            i.id != excluding?.id && i.title.lowercased() == trimmed.lowercased()
        }
        if conflict { throw ItemCRUDError.duplicateTitle }
    }

    // MARK: - Item CRUD (ItemCollection-scoped)

    @discardableResult
    func createItem(name: String, icon: String? = nil, in collection: ItemCollection, type itemType: ItemType) async throws -> Item {
        do {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let existing = itemsByCollection[collection.id] ?? []
            try enforceTitleUniqueness(trimmed, among: existing)

            let now = Date()
            let item = Item(
                id: ULID.generate(), title: trimmed, icon: icon, description: "",
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: now, modifiedAt: now
            )
            let url = NexusPaths.itemFileURL(forTitle: trimmed, in: collection.folderURL)
            try item.save(to: url)

            if let updater = indexUpdater {
                do { try updater.upsertItem(item, itemTypeID: itemType.id, itemCollectionID: collection.id) } catch { self.pendingError = error }
            }

            var arr = existing
            arr.append(item)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: collection.itemOrder,
                titleKeyPath: \Item.title
            )
            itemsByCollection[collection.id] = arr
            _ = itemType  // schema validation arrives Phase 6
            return item
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renameItem(
        _ item: Item, to newName: String, in collection: ItemCollection, type itemType: ItemType
    ) async throws {
        do {
            let trimmed = newName.trimmingCharacters(in: .whitespaces)
            let existing = itemsByCollection[collection.id] ?? []
            try enforceTitleUniqueness(trimmed, among: existing, excluding: item)

            let oldURL = NexusPaths.itemFileURL(forTitle: item.title, in: collection.folderURL)
            let newURL = NexusPaths.itemFileURL(forTitle: trimmed, in: collection.folderURL)
            var updated = item
            updated.title = trimmed
            updated.modifiedAt = Date()
            try Filesystem.renameFile(from: oldURL, to: newURL)
            do {
                try updated.save(to: newURL)
            } catch let saveError {
                do {
                    try Filesystem.renameFile(from: newURL, to: oldURL)
                    throw saveError
                } catch let revertError {
                    let combined = RenameAtomicityError(saveError: saveError, revertError: revertError)
                    self.pendingError = combined
                    throw combined
                }
            }

            if let updater = indexUpdater {
                do { try updater.upsertItem(updated, itemTypeID: itemType.id, itemCollectionID: collection.id) } catch { self.pendingError = error }
            }

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == item.id }) {
                arr[i] = updated
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: collection.itemOrder,
                    titleKeyPath: \Item.title
                )
            }
            itemsByCollection[collection.id] = arr
            _ = itemType  // schema validation arrives Phase 6
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func updateItem(_ item: Item, in collection: ItemCollection, type itemType: ItemType) async throws {
        do {
            let trimmed = item.title.trimmingCharacters(in: .whitespaces)
            let existing = itemsByCollection[collection.id] ?? []
            try enforceTitleUniqueness(trimmed, among: existing, excluding: item)

            var updated = item
            updated.modifiedAt = Date()
            let url = NexusPaths.itemFileURL(forTitle: trimmed, in: collection.folderURL)
            try updated.save(to: url)

            if let updater = indexUpdater {
                do { try updater.upsertItem(updated, itemTypeID: itemType.id, itemCollectionID: collection.id) } catch { self.pendingError = error }
            }

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == item.id }) {
                arr[i] = updated
            }
            itemsByCollection[collection.id] = arr
            _ = itemType  // schema validation arrives Phase 6
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func deleteItem(_ item: Item, in collection: ItemCollection) async throws {
        do {
            let url = NexusPaths.itemFileURL(forTitle: item.title, in: collection.folderURL)
            try Filesystem.moveToTrash(url, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deleteItem(id: item.id) } catch { self.pendingError = error }
            }
            var arr = itemsByCollection[collection.id] ?? []
            arr.removeAll { $0.id == item.id }
            itemsByCollection[collection.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
        // Best-effort cascade: move the entity's attachments folder to trash.
        let attachmentsURL = NexusPaths.attachmentsDir(for: item.id, in: nexus.rootURL)
        if FileManager.default.fileExists(atPath: attachmentsURL.path) {
            try? Filesystem.moveToTrash(attachmentsURL, in: nexus)
        }
    }

    // MARK: - Item CRUD (Item-Type-root)

    @discardableResult
    func createItem(name: String, icon: String? = nil, inTypeRoot itemType: ItemType) async throws -> Item {
        do {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let existing = itemsByTypeRoot[itemType.id] ?? []
            try enforceTitleUniqueness(trimmed, among: existing)

            let now = Date()
            let item = Item(
                id: ULID.generate(), title: trimmed, icon: icon, description: "",
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: now, modifiedAt: now
            )
            let url = NexusPaths.itemFileURL(forTitle: trimmed, in: folderURL(for: itemType))
            try item.save(to: url)

            if let updater = indexUpdater {
                do { try updater.upsertItem(item, itemTypeID: itemType.id, itemCollectionID: nil) } catch { self.pendingError = error }
            }

            var arr = existing
            arr.append(item)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: itemType.itemOrder,
                titleKeyPath: \Item.title
            )
            itemsByTypeRoot[itemType.id] = arr
            return item
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renameItem(_ item: Item, to newName: String, inTypeRoot itemType: ItemType) async throws {
        do {
            let trimmed = newName.trimmingCharacters(in: .whitespaces)
            let existing = itemsByTypeRoot[itemType.id] ?? []
            try enforceTitleUniqueness(trimmed, among: existing, excluding: item)

            let folder = folderURL(for: itemType)
            let oldURL = NexusPaths.itemFileURL(forTitle: item.title, in: folder)
            let newURL = NexusPaths.itemFileURL(forTitle: trimmed, in: folder)
            var updated = item
            updated.title = trimmed
            updated.modifiedAt = Date()
            try Filesystem.renameFile(from: oldURL, to: newURL)
            do {
                try updated.save(to: newURL)
            } catch let saveError {
                do {
                    try Filesystem.renameFile(from: newURL, to: oldURL)
                    throw saveError
                } catch let revertError {
                    let combined = RenameAtomicityError(saveError: saveError, revertError: revertError)
                    self.pendingError = combined
                    throw combined
                }
            }

            if let updater = indexUpdater {
                do { try updater.upsertItem(updated, itemTypeID: itemType.id, itemCollectionID: nil) } catch { self.pendingError = error }
            }

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == item.id }) {
                arr[i] = updated
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: itemType.itemOrder,
                    titleKeyPath: \Item.title
                )
            }
            itemsByTypeRoot[itemType.id] = arr
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func updateItem(_ item: Item, inTypeRoot itemType: ItemType) async throws {
        do {
            let trimmed = item.title.trimmingCharacters(in: .whitespaces)
            let existing = itemsByTypeRoot[itemType.id] ?? []
            try enforceTitleUniqueness(trimmed, among: existing, excluding: item)

            var updated = item
            updated.modifiedAt = Date()
            let url = NexusPaths.itemFileURL(forTitle: trimmed, in: folderURL(for: itemType))
            try updated.save(to: url)

            if let updater = indexUpdater {
                do { try updater.upsertItem(updated, itemTypeID: itemType.id, itemCollectionID: nil) } catch { self.pendingError = error }
            }

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == item.id }) {
                arr[i] = updated
            }
            itemsByTypeRoot[itemType.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func deleteItem(_ item: Item, inTypeRoot itemType: ItemType) async throws {
        do {
            let url = NexusPaths.itemFileURL(forTitle: item.title, in: folderURL(for: itemType))
            try Filesystem.moveToTrash(url, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deleteItem(id: item.id) } catch { self.pendingError = error }
            }
            var arr = itemsByTypeRoot[itemType.id] ?? []
            arr.removeAll { $0.id == item.id }
            itemsByTypeRoot[itemType.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
        // Best-effort cascade: move the entity's attachments folder to trash.
        let attachmentsURL = NexusPaths.attachmentsDir(for: item.id, in: nexus.rootURL)
        if FileManager.default.fileExists(atPath: attachmentsURL.path) {
            try? Filesystem.moveToTrash(attachmentsURL, in: nexus)
        }
    }

    // MARK: - Move (same-Type, between ItemCollections)

    /// Moves `item` from one ItemCollection to another within the SAME ItemType.
    /// No property strip — both Collections share the same Type schema.
    /// Atomically rewrites the item file at the destination path.
    func moveItemBetweenCollections(
        _ item: Item,
        from source: ItemCollection,
        to destination: ItemCollection,
        in itemType: ItemType
    ) async throws {
        do {
            let srcURL = NexusPaths.itemFileURL(forTitle: item.title, in: source.folderURL)
            let destURL = NexusPaths.itemFileURL(forTitle: item.title, in: destination.folderURL)

            let tx = SchemaTransaction()
            try tx.stage(item, to: destURL)
            try tx.commit()

            try Filesystem.deleteFile(at: srcURL)

            var updated = item
            // `Item.url` isn't stored — URL is always derived from title+folder; no field to patch.

            if let updater = indexUpdater {
                do {
                    try updater.upsertItem(updated, itemTypeID: itemType.id, itemCollectionID: destination.id)
                } catch {
                    self.pendingError = error
                }
            }

            var srcArr = itemsByCollection[source.id] ?? []
            srcArr.removeAll { $0.id == item.id }
            itemsByCollection[source.id] = srcArr

            var dstArr = itemsByCollection[destination.id] ?? []
            dstArr.append(updated)
            dstArr = OrderResolver.resolve(
                dstArr,
                persistedOrder: destination.itemOrder,
                titleKeyPath: \Item.title
            )
            itemsByCollection[destination.id] = dstArr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Move (cross-Type, with property strip + paired-relation back-ref clear)

    /// Moves `item` from one ItemType (and optional ItemCollection) to a different
    /// ItemType (and optional ItemCollection). Performs:
    ///
    /// 1. **Strip:** property values whose property NAMES don't exist on
    ///    `destination` are removed from the item's properties dict.
    /// 2. **Paired-relation back-ref clear:** for each relation property with a
    ///    `dualProperty` config that is being stripped, the reverse entries on
    ///    target entities are cleared.
    /// 3. **Atomic commit:** all writes go through a single `SchemaTransaction`.
    ///
    /// If `source.id == destination.id`, use `moveItemBetweenCollections` instead.
    func moveItemAcrossTypes(
        _ item: Item,
        from source: ItemType,
        fromCollection: ItemCollection?,
        to destination: ItemType,
        toCollection: ItemCollection?
    ) async throws {
        precondition(
            source.id != destination.id,
            "moveItemAcrossTypes requires distinct source and destination ItemTypes."
        )
        do {
            // 1. Strip set by name comparison.
            let destNames = Set(destination.properties.map { $0.name })
            let strippedDefs = source.properties.filter { !destNames.contains($0.name) }
            let strippedIDs = Set(strippedDefs.map { $0.id })

            // 2. Build updated item with stripped properties removed.
            var updatedItem = item
            for id in strippedIDs {
                updatedItem.properties.removeValue(forKey: id)
            }
            updatedItem.modifiedAt = Date()

            // 3. Compute destination URL.
            let destFolder: URL
            if let dstColl = toCollection {
                destFolder = dstColl.folderURL
            } else {
                destFolder = folderURL(for: destination)
            }
            let destURL = NexusPaths.itemFileURL(forTitle: item.title, in: destFolder)

            // 4. Stage the rewritten item at destination.
            let tx = SchemaTransaction()
            try tx.stage(updatedItem, to: destURL)

            // 5. Stage paired-relation back-ref clears for stripped relations.
            for def in strippedDefs where def.type == .relation {
                guard let dual = def.dualProperty else { continue }
                guard let value = item.properties[def.id] else { continue }
                let targetIDs = Self.extractRelationIDs(from: value)
                guard !targetIDs.isEmpty else { continue }

                try Self.stageBackRefClear(
                    sourceEntityID: item.id,
                    reversePropertyID: dual.syncedPropertyID,
                    onTypeID: dual.syncedPropertyDefinedOnTypeID,
                    targetEntityIDs: targetIDs,
                    tx: tx,
                    nexus: nexus
                )
            }

            // 6. Atomic commit.
            try tx.commit()

            // 7. Remove source file.
            let srcFolder: URL
            if let srcColl = fromCollection {
                srcFolder = srcColl.folderURL
            } else {
                srcFolder = folderURL(for: source)
            }
            let srcURL = NexusPaths.itemFileURL(forTitle: item.title, in: srcFolder)
            try Filesystem.deleteFile(at: srcURL)

            // 8. Update index.
            if let updater = indexUpdater {
                do {
                    try updater.upsertItem(
                        updatedItem,
                        itemTypeID: destination.id,
                        itemCollectionID: toCollection?.id
                    )
                } catch {
                    self.pendingError = error
                }
            }

            // 9. Update in-memory caches.
            if let srcColl = fromCollection {
                var arr = itemsByCollection[srcColl.id] ?? []
                arr.removeAll { $0.id == item.id }
                itemsByCollection[srcColl.id] = arr
            } else {
                var arr = itemsByTypeRoot[source.id] ?? []
                arr.removeAll { $0.id == item.id }
                itemsByTypeRoot[source.id] = arr
            }

            if let dstColl = toCollection {
                var arr = itemsByCollection[dstColl.id] ?? []
                arr.append(updatedItem)
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: dstColl.itemOrder,
                    titleKeyPath: \Item.title
                )
                itemsByCollection[dstColl.id] = arr
            } else {
                var arr = itemsByTypeRoot[destination.id] ?? []
                arr.append(updatedItem)
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: destination.itemOrder,
                    titleKeyPath: \Item.title
                )
                itemsByTypeRoot[destination.id] = arr
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Private move helpers

    private static func extractRelationIDs(from value: PropertyValue) -> [String] {
        switch value {
        case .relation(let ids): return ids
        case .multiSelect(let ids): return ids
        default: return []
        }
    }

    /// Stages back-ref clears on files owned by the Type identified by `onTypeID`.
    /// Walks `.md` (PageType) or `.json` (ItemType) files and removes `sourceEntityID`
    /// from the `reversePropertyID` value on matching entities.
    private static func stageBackRefClear(
        sourceEntityID: String,
        reversePropertyID: String,
        onTypeID: String,
        targetEntityIDs: [String],
        tx: SchemaTransaction,
        nexus: Nexus
    ) throws {
        let targetSet = Set(targetEntityIDs)
        let nexusRoot = nexus.rootURL

        let allDirs = (try? FileManager.default.contentsOfDirectory(
            at: nexusRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for dir in allDirs {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir),
                  isDir.boolValue
            else { continue }

            // Check for PageType sidecar.
            let ptSidecar = dir.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
            if FileManager.default.fileExists(atPath: ptSidecar.path) {
                if let pt = try? AtomicJSON.decode(PageType.self, from: ptSidecar),
                   pt.id == onTypeID
                {
                    let mdFiles = (try? Filesystem.descendantFiles(
                        of: dir,
                        where: { $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix("_") }
                    )) ?? []
                    for mdURL in mdFiles {
                        var (fm, body) = try AtomicYAMLMarkdown.load(PageFrontmatter.self, from: mdURL)
                        guard targetSet.contains(fm.id),
                              let val = fm.properties[reversePropertyID]
                        else { continue }
                        fm.properties[reversePropertyID] = removeID(sourceEntityID, from: val)
                        let data = try AtomicYAMLMarkdown.encode(frontmatter: fm, body: body)
                        tx.stage(payload: data, to: mdURL)
                    }
                    return
                }
            }

            // Check for ItemType sidecar.
            let itSidecar = dir.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
            if FileManager.default.fileExists(atPath: itSidecar.path) {
                if let it = try? AtomicJSON.decode(ItemType.self, from: itSidecar),
                   it.id == onTypeID
                {
                    let jsonFiles = (try? Filesystem.descendantFiles(
                        of: dir,
                        where: {
                            $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix("_")
                        }
                    )) ?? []
                    for jsonURL in jsonFiles {
                        var targetItem = try AtomicJSON.decode(Item.self, from: jsonURL)
                        guard targetSet.contains(targetItem.id),
                              let val = targetItem.properties[reversePropertyID]
                        else { continue }
                        targetItem.properties[reversePropertyID] = removeID(sourceEntityID, from: val)
                        tx.stage(payload: try AtomicJSON.encode(targetItem), to: jsonURL)
                    }
                    return
                }
            }
        }
    }

    private static func removeID(_ idToRemove: String, from value: PropertyValue) -> PropertyValue? {
        switch value {
        case .relation(let ids):
            let filtered = ids.filter { $0 != idToRemove }
            return filtered.isEmpty ? .null : .relation(filtered)
        case .multiSelect(let ids):
            let filtered = ids.filter { $0 != idToRemove }
            return filtered.isEmpty ? .null : .multiSelect(filtered)
        default:
            return value
        }
    }

    // MARK: - Update single property value (Task 14 — v0.3.1)

    /// Atomic single-property value write on an Item. Reads the current Item
    /// from disk (since Item carries an in-memory snapshot but value writes
    /// originate from contexts that may not have the fresh disk state),
    /// mutates `properties[propertyID]`, updates modifiedAt, writes back
    /// via AtomicJSON, then refreshes the in-memory cache + SQLite index.
    ///
    /// Mirror of PageContentManager.updatePageProperty (Task 13). Same
    /// nil-clears-key semantics. Same deferral of dual-relation reverse-
    /// mirror (Item ↔ Page relations + Item ↔ Item relations both wire up
    /// via DualRelationCoordinator in a v0.3.1.x follow-up).
    ///
    /// Caller passes `collection: nil` for Item-Type-root items.
    func updateItemProperty(
        _ item: Item,
        propertyID: String,
        newValue: PropertyValue?,
        type itemType: ItemType,
        collection: ItemCollection?
    ) async throws {
        do {
            let url: URL
            if let collection {
                url = NexusPaths.itemFileURL(forTitle: item.title, in: collection.folderURL)
            } else {
                url = NexusPaths.itemFileURL(forTitle: item.title, in: folderURL(for: itemType))
            }

            var updated = try AtomicJSON.decode(Item.self, from: url)
            updated.title = item.title  // filename derives title (not persisted on Item)
            if let newValue {
                updated.properties[propertyID] = newValue
            } else {
                updated.properties.removeValue(forKey: propertyID)
            }
            updated.modifiedAt = Date()

            try AtomicJSON.write(updated, to: url)

            if let collection {
                if var arr = itemsByCollection[collection.id],
                   let i = arr.firstIndex(where: { $0.id == item.id })
                {
                    arr[i] = updated
                    itemsByCollection[collection.id] = arr
                }
            } else {
                if var arr = itemsByTypeRoot[itemType.id],
                   let i = arr.firstIndex(where: { $0.id == item.id })
                {
                    arr[i] = updated
                    itemsByTypeRoot[itemType.id] = arr
                }
            }

            if let updater = indexUpdater {
                do {
                    try updater.upsertItem(
                        updated,
                        itemTypeID: itemType.id,
                        itemCollectionID: collection?.id
                    )
                } catch {
                    self.pendingError = error
                }
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }
}

/// Errors surfaced by `ItemContentManager` CRUD methods during the
/// Task 5.5 transitional window. Phase 6 replaces these with the
/// upgraded `ItemValidator` typed on `ItemType`.
enum ItemCRUDError: Error, LocalizedError, Equatable {
    case emptyTitle
    case invalidTitleCharacters
    case duplicateTitle

    var errorDescription: String? {
        switch self {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle: return "An Item with that name already exists."
        }
    }
}
