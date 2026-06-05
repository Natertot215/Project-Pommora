import Foundation

/// CRUD methods for Items across both ItemCollection-scoped and
/// Item-Type-root-scoped storage. Split out from `ItemContentManager.swift`
/// for legibility, mirroring `PageContentManager+CRUD.swift`.
///
/// **ParadigmV2 (Task 5.5 — stub-and-progressively-replace):**
/// - Save-time schema validation via `ItemValidator.validate` is wired into
///   all six CRUD entry points; it sources the property schema from
///   `itemType.properties` and validates tier values + the body cap.
/// - The inline `enforceTitleUniqueness` check coexists with it: titles are
///   validated for same-container collisions while `ItemValidator` covers
///   schema / tier / body-cap. Matches `PageContentManager`'s shape.
/// - Item-Type-root paths assume the `<nexus>/Items/<TypeFolder>/` wrapper
///   exists; NexusAdopter materializes the wrapper.
///
/// Every CRUD method:
/// - Wraps its body in `do { … } catch { self.pendingError = error; throw error }`
///   so the sidebar toast can surface failures.
/// - For rename methods that do two filesystem ops (rename + save), applies
///   the rename-atomicity rollback pattern; if the revert ALSO fails it
///   surfaces a `RenameAtomicityError`.
extension ItemContentManager {

    // MARK: - Title uniqueness
    //
    // The dedicated same-container title-collision check; runs alongside
    // `ItemValidator` (which covers schema / tier / body-cap). The collision
    // rule is delegated to the shared `NameCollisionValidator` (one source of
    // truth, Pages + Items identical); the empty / invalid-character checks
    // stay here as Item-side concerns.
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
        try NameCollisionValidator.validate(
            desiredTitle: trimmed, siblings: siblings, excludingID: excluding?.id,
            else: ItemCRUDError.duplicateTitle  // preserve the Item-side contract
        )
    }

    // MARK: - Save-time schema validation (Phase 6)
    //
    // Single call shape for `ItemValidator.validate` across all six CRUD entry
    // points (one source of truth). Sources the property schema from the Item
    // Type and the live tier-lookup context from `contextProvider()`. The
    // `description` is the Item's body (Shape A) — capped at
    // `ItemValidator.maxDescriptionLength` source characters.
    fileprivate func validate(_ item: Item, type itemType: ItemType) throws {
        try ItemValidator.validate(
            title: item.title,
            tier1: item.tier1, tier2: item.tier2, tier3: item.tier3,
            description: item.description,
            properties: item.properties,
            itemType: itemType,
            context: contextProvider()
        )
    }

    /// Defense-in-depth for the create write path: a freshly-created Item mints
    /// a new id, so any file already at its target URL is owned by a *different*
    /// entity. Refuse the write rather than clobber it — even if a caller ever
    /// skipped `enforceTitleUniqueness` (e.g. a stale in-memory sibling list).
    /// Delegates to the shared `Filesystem.guardNoFile` (Pages / Items / Agenda
    /// share one shape) but keeps the Item-side `duplicateTitle` wording.
    fileprivate func guardNoOverwrite(at url: URL) throws {
        try Filesystem.guardNoFile(at: url, else: ItemCRUDError.duplicateTitle)
    }

    // MARK: - Item CRUD (ItemCollection-scoped)

    @discardableResult
    func createItem(
        name: String, icon: String? = nil, in collection: ItemCollection, type itemType: ItemType
    ) async throws -> Item {
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
            try validate(item, type: itemType)
            let url = NexusPaths.itemFileURL(forTitle: trimmed, in: collection.folderURL)
            try guardNoOverwrite(at: url)
            try item.save(to: url)

            if let updater = indexUpdater {
                do { try updater.upsertItem(item, itemTypeID: itemType.id, itemCollectionID: collection.id) } catch {
                    self.pendingError = error
                }
            }

            var arr = existing
            arr.append(item)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: collection.itemOrder,
                titleKeyPath: \Item.title
            )
            itemsByCollection[collection.id] = arr
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
            // TITLE-only validation (via `enforceTitleUniqueness` above): a rename
            // changes only the filename, so it must NOT re-run the whole-item
            // `validate` (body-cap / schema / tier). A drifted Item carried verbatim
            // by migration / `loadLenient` (>1000-char body, out-of-schema property)
            // would otherwise throw on data the rename never touched. create/update
            // keep whole-item validation — they set the data.
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
                do { try updater.upsertItem(updated, itemTypeID: itemType.id, itemCollectionID: collection.id) } catch {
                    self.pendingError = error
                }
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
            try validate(updated, type: itemType)
            let url = NexusPaths.itemFileURL(forTitle: trimmed, in: collection.folderURL)
            try updated.save(to: url)

            if let updater = indexUpdater {
                do { try updater.upsertItem(updated, itemTypeID: itemType.id, itemCollectionID: collection.id) } catch {
                    self.pendingError = error
                }
            }

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == item.id }) {
                arr[i] = updated
            }
            itemsByCollection[collection.id] = arr
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
            try validate(item, type: itemType)
            let url = NexusPaths.itemFileURL(forTitle: trimmed, in: folderURL(for: itemType))
            try guardNoOverwrite(at: url)
            try item.save(to: url)

            if let updater = indexUpdater {
                do { try updater.upsertItem(item, itemTypeID: itemType.id, itemCollectionID: nil) } catch {
                    self.pendingError = error
                }
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
            // TITLE-only validation (see the in-collection `renameItem`): a rename
            // changes only the filename, so it must NOT re-run whole-item `validate`
            // on pre-existing drift it didn't introduce.
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
                do { try updater.upsertItem(updated, itemTypeID: itemType.id, itemCollectionID: nil) } catch {
                    self.pendingError = error
                }
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
            try validate(updated, type: itemType)
            let url = NexusPaths.itemFileURL(forTitle: trimmed, in: folderURL(for: itemType))
            try updated.save(to: url)

            if let updater = indexUpdater {
                do { try updater.upsertItem(updated, itemTypeID: itemType.id, itemCollectionID: nil) } catch {
                    self.pendingError = error
                }
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

    // MARK: - Draft commit seam (T4.5)

    /// The single testable persist seam the LIVE Item Window's `commitSave`
    /// routes through. Applies the window's draft title / icon / description /
    /// properties onto `item`, then persists via the right `updateItem` path
    /// (Collection-scoped when `collection` is non-nil, else Type-root). Title is
    /// trimmed; a blank icon clears it to `nil`. `properties` flows through
    /// unchanged — the live window keeps property rows read-only for now, but the
    /// machinery carries the dict so a property-editing UI can be added later
    /// without touching this seam.
    ///
    /// Pure-of-view: takes plain values, returns nothing, and reuses the existing
    /// `updateItem` (which stamps `modifiedAt`, validates, saves, and upserts the
    /// index) — so a unit test can apply an edit and assert the round-trip.
    func commitItemEdits(
        _ item: Item,
        title: String,
        icon: String,
        description: String,
        properties: [String: PropertyValue],
        type itemType: ItemType,
        collection: ItemCollection?
    ) async throws {
        var updated = item
        updated.title = title.trimmingCharacters(in: .whitespaces)
        let trimmedIcon = icon.trimmingCharacters(in: .whitespaces)
        updated.icon = trimmedIcon.isEmpty ? nil : trimmedIcon
        updated.description = description
        updated.properties = properties

        if let collection {
            try await updateItem(updated, in: collection, type: itemType)
        } else {
            try await updateItem(updated, inTypeRoot: itemType)
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

            // Refuse to clobber a different same-title Item already in the
            // destination. `SchemaTransaction.commit` would back up + drop the
            // existing file (no renameFile here to catch it). Item-side wording.
            try guardNoOverwrite(at: destURL)

            // Stage the rewritten Item at the destination as a `.md` envelope,
            // preserving any foreign frontmatter from the source file (deleted
            // AFTER commit, so still present at stage time).
            let data = try AtomicYAMLMarkdown.encode(
                frontmatter: item.frontmatter, body: item.description,
                preservingFrom: srcURL, modeledKeys: ItemFrontmatter.modeledKeys)
            let tx = SchemaTransaction()
            tx.stage(payload: data, to: destURL)
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

    // MARK: - Move (cross-Type, with property strip)

    /// Moves `item` from one ItemType (and optional ItemCollection) to a different
    /// ItemType (and optional ItemCollection). Performs:
    ///
    /// 1. **Strip:** property values whose property NAMES don't exist on
    ///    `destination` are removed from the item's properties dict.
    /// 2. **Atomic commit:** all writes go through a single `SchemaTransaction`.
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

            // 3. Compute destination + source `.md` URLs up front so the move can
            //    preserve foreign frontmatter from the source (deleted only AFTER
            //    commit).
            let destFolder: URL
            if let dstColl = toCollection {
                destFolder = dstColl.folderURL
            } else {
                destFolder = folderURL(for: destination)
            }
            let destURL = NexusPaths.itemFileURL(forTitle: item.title, in: destFolder)

            let srcFolder: URL
            if let srcColl = fromCollection {
                srcFolder = srcColl.folderURL
            } else {
                srcFolder = folderURL(for: source)
            }
            let srcURL = NexusPaths.itemFileURL(forTitle: item.title, in: srcFolder)

            // 3a. Refuse to clobber a different same-title Item already in the
            //     destination Type/Collection (same data-loss vector as the
            //     between-Collections move). Item-side `duplicateTitle` wording.
            try guardNoOverwrite(at: destURL)

            // 4. Stage the rewritten item at destination as a `.md` envelope,
            //    preserving any foreign frontmatter from the source file.
            let tx = SchemaTransaction()
            let destData = try AtomicYAMLMarkdown.encode(
                frontmatter: updatedItem.frontmatter, body: updatedItem.description,
                preservingFrom: srcURL, modeledKeys: ItemFrontmatter.modeledKeys)
            tx.stage(payload: destData, to: destURL)

            // 5. Atomic commit.
            try tx.commit()

            // 6. Remove source file (resolved at step 3).
            try Filesystem.deleteFile(at: srcURL)

            // 7. Update index.
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

            // 8. Update in-memory caches.
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

    // MARK: - Update single property value (Task 14 — v0.3.1)

    /// Atomic single-property value write on an Item. Reads the current Item
    /// from disk (since Item carries an in-memory snapshot but value writes
    /// originate from contexts that may not have the fresh disk state),
    /// mutates `properties[propertyID]`, updates modifiedAt, writes back
    /// via `Item.save` (a preserving `.md` envelope write), then refreshes
    /// the in-memory cache + SQLite index.
    ///
    /// Mirror of PageContentManager.updatePageProperty (Task 13). Same
    /// nil-clears-key semantics.
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
            let folder = collection?.folderURL ?? folderURL(for: itemType)
            let url = NexusPaths.itemFileURL(forTitle: item.title, in: folder)

            var updated = try Item.load(from: url)
            updated.title = item.title  // filename derives title (not persisted on Item)
            if case .relation(let ids)? = newValue {
                updated.setRelationIDs(ids, forPropertyID: propertyID)  // tier→root, user→properties, empty→omit
            } else if let newValue {
                updated.properties[propertyID] = newValue
            } else {
                updated.properties.removeValue(forKey: propertyID)
            }
            updated.modifiedAt = Date()

            // Preserving `.md` envelope write.
            try updated.save(to: url)

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

    // MARK: - Update icon

    /// Persists a new icon onto an Item — sets `icon` on a copy and routes
    /// through the existing `updateItem` save path (atomic write + `modifiedAt`
    /// bump + index upsert + in-memory sync). Type-root vs in-collection picks
    /// the matching overload.
    func updateItemIcon(
        _ item: Item, to icon: String?, type itemType: ItemType, collection: ItemCollection?
    ) async throws {
        var updated = item
        updated.icon = icon
        if let collection {
            try await updateItem(updated, in: collection, type: itemType)
        } else {
            try await updateItem(updated, inTypeRoot: itemType)
        }
    }

    // MARK: - Context-delete cascade (Phase 18b)

    /// Removes a deleted Context's ID from the `tier` array of every Item that
    /// references it. Source-side cascade: invoked at the Context-delete call
    /// site (×4, once per content manager) **before** the Context file is removed.
    ///
    /// Mirrors `PageContentManager.unlinkTier` exactly — see that method for the
    /// full contract. Each Item that references `contextID` is located from the
    /// index (no in-hand URL), loaded, mutated through the `setRelationIDs`
    /// adapter (tiers route to the Item root, NOT `properties["_tierN"]`),
    /// atomically rewritten, its in-memory cache entry refreshed if loaded, and
    /// re-indexed so the stale `relations` rows reconcile away.
    ///
    /// Resilient per-entity: an Item that can't be located or loaded is skipped
    /// (the first failure is recorded on `pendingError`) so one bad file never
    /// aborts the cascade.
    func unlinkTier(contextID: String, tier: Int, index: PommoraIndex) async throws {
        guard let tierPropID = ReservedPropertyID.tierPropertyID(forTier: tier) else { return }

        let refs = try await IndexQuery(index).incomingRelations(targetID: contextID)
        let itemRefs = refs.filter { $0.kind == .item }

        for ref in itemRefs {
            do {
                guard
                    let container = try await IndexQuery(index)
                        .entityContainer(id: ref.id, kind: .item),
                    let url = locateItemFile(id: ref.id, container: container)
                else { continue }

                var item = try Item.load(from: url)
                let current = item.relationIDs(forPropertyID: tierPropID)
                guard current.contains(contextID) else { continue }

                item.setRelationIDs(current.filter { $0 != contextID }, forPropertyID: tierPropID)
                item.modifiedAt = Date()
                try item.save(to: url)

                refreshItemCache(item, container: container)

                if let updater = indexUpdater {
                    do {
                        try updater.upsertItem(
                            item,
                            itemTypeID: container.typeID,
                            itemCollectionID: container.collectionID
                        )
                    } catch {
                        self.pendingError = error
                    }
                }
            } catch {
                // Continue-on-individual-failure: a single unreadable / unwritable
                // Item must not block the rest of the cascade.
                self.pendingError = error
                continue
            }
        }
    }

    /// Locates an Item's `.md` file from its index container. The folder is built
    /// from the container titles; the file is found by walking that folder and
    /// matching `id` — nesting-proof for Type-root Items that physically live in a
    /// deeper non-Collection sub-folder (whose files roll up to the Type root with
    /// `item_collection_id == nil`).
    private func locateItemFile(id: String, container: EntityContainer) -> URL? {
        let folder: URL
        if let collectionTitle = container.collectionTitle {
            folder = NexusPaths.itemCollectionFolderURL(
                in: nexus.rootURL,
                typeFolderName: container.typeTitle,
                collectionFolderName: collectionTitle
            )
        } else {
            folder = NexusPaths.itemTypeFolderURL(
                in: nexus.rootURL, typeFolderName: container.typeTitle
            )
        }
        // Fast path: the canonical title-derived `.md` file.
        let candidate = NexusPaths.itemFileURL(forTitle: container.entityTitle, in: folder)
        if Filesystem.fileExists(at: candidate),
            let loaded = try? Item.load(from: candidate),
            loaded.id == id
        {
            return candidate
        }
        // Fall back to a descendant walk matching by id (handles nested Type-root
        // Items + any title/filename divergence).
        let matches =
            (try? Filesystem.descendantFiles(of: folder) { url in
                url.pathExtension == "md" && !url.lastPathComponent.hasPrefix("_")
            }) ?? []
        for url in matches {
            if let loaded = try? Item.load(from: url), loaded.id == id {
                return url
            }
        }
        return nil
    }

    /// Refreshes the in-memory `Item` for `updated` in whichever cache bucket
    /// holds it (Collection-scoped or Type-root), if present. No-op when the Item
    /// isn't loaded — the on-disk write + index upsert are the source of truth.
    private func refreshItemCache(_ updated: Item, container: EntityContainer) {
        if let collectionID = container.collectionID {
            if var arr = itemsByCollection[collectionID],
                let i = arr.firstIndex(where: { $0.id == updated.id })
            {
                arr[i] = updated
                itemsByCollection[collectionID] = arr
            }
        } else {
            if var arr = itemsByTypeRoot[container.typeID],
                let i = arr.firstIndex(where: { $0.id == updated.id })
            {
                arr[i] = updated
                itemsByTypeRoot[container.typeID] = arr
            }
        }
    }
}

/// Errors surfaced by `ItemContentManager` CRUD methods for CRUD / IO
/// failures (e.g. not-found, overwrite, empty / duplicate title). Separate
/// concern from `ItemValidator` (schema / tier / body-cap); the two coexist —
/// `ItemValidator` did not replace these errors.
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
