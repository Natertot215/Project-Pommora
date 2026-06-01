import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderPageTypes/Collections

@MainActor
@Observable
final class PageTypeManager {
    private(set) var types: [PageType] = []
    private(set) var pageCollectionsByType: [String: [PageCollection]] = [:]
    var pendingError: (any Error)?

    private let nexus: Nexus

    /// Current Nexus ID — used by the drag system's cross-window guard.
    var nexusID: String { nexus.id }

    /// Injected by NexusManager in Phase E.7. Nil until wired; CRUD methods
    /// call it post-commit as a best-effort non-fatal write (filesystem is canonical).
    var indexUpdater: IndexUpdater?

    /// Cross-manager in-memory refresh hook. Injected in `ContentView.constructManagers`
    /// (snapshot-closure pattern, quirk #5). Given any Type ID, the closure finds the
    /// owning manager (PageTypeManager / ItemTypeManager / Agenda) and reloads that type
    /// from disk into its in-memory `types`. Paired-relation create/delete call it for the
    /// CROSS-side target (which lives in the OTHER manager) so the reverse property
    /// appears/disappears immediately instead of only after restart. Same-manager targets
    /// are reloaded inline and never routed here. Nil until wired.
    var reloadTypeByID: (@MainActor (String) -> Void)?

    /// Backing store for the lazily-constructed `schemaAdapter` (declared in the
    /// per-type schema-adapter extension). Held here because stored properties can't
    /// live on an extension. Not observed — purely an internal service bridge.
    @ObservationIgnored fileprivate var _schemaAdapter: PageSchemaAdapter?

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func pageCollections(in pageType: PageType) -> [PageCollection] {
        pageCollectionsByType[pageType.id] ?? []
    }

    /// Reloads a single PageType from disk into the in-memory `types` array by ID.
    /// No-op if the ID isn't one of this manager's types (the cross-manager router
    /// only dispatches IDs it has already matched to this manager). Best-effort: a
    /// load failure leaves the stale in-memory copy in place (disk is canonical; a
    /// later loadAll converges). Used by the cross-manager `reloadTypeByID` hook so a
    /// paired-relation reverse created/deleted by the OTHER manager surfaces here
    /// without a restart.
    func reloadTypeFromDisk(id: String) {
        guard let i = types.firstIndex(where: { $0.id == id }) else { return }
        let meta = NexusPaths.vaultMetadataURL(forTitle: types[i].title, in: nexus)
        if let reloaded = try? PageType.load(from: meta) {
            types[i] = reloaded
        }
    }

    // MARK: - Load

    func loadAll() async {
        do {
            // flatlayout: PageType folders sit at the Nexus root. Discovery
            // filters folders by presence of `_pagetype.json`; folders carrying
            // any of the other per-kind sidecars (Items/Agenda/Collection) or
            // no recognized sidecar are skipped. NexusAdopter is the single
            // canonical migration surface — it surfaces unrecognized / legacy
            // folders to the user via the preview sheet on launch. No in-loader
            // auto-heal here (would race the adopter and produce inconsistent
            // state).
            let root = nexus.rootURL

            let topLevel = try Filesystem.childFolders(of: root)
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .filter { !$0.lastPathComponent.hasPrefix("_") }

            var loadedTypes: [PageType] = []
            var loadedCols: [String: [PageCollection]] = [:]

            for folder in topLevel {
                let metaURL = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
                guard Filesystem.fileExists(at: metaURL),
                    var pageType = try? PageType.load(from: metaURL)
                else { continue }

                // Default-view migration (Task 5, Phase A — v0.3.1). If the
                // PageType has no saved views, mint a Table view that exposes
                // every user-defined property as a column. Idempotent — the
                // `views.isEmpty` gate is the only mutation trigger. Best-
                // effort save: failures fall through and the next loadAll
                // tries again (no user data lost; matches quirk #15's
                // defensive-on-load pattern).
                if pageType.views.isEmpty {
                    pageType.views = [
                        SavedView.defaultTable(visiblePropertyIDs: pageType.properties.map(\.id))
                    ]
                    try? pageType.save(to: metaURL)
                }
                loadedTypes.append(pageType)

                // Discover PageCollections (sub-folders with `_pagecollection.json`; skip _- and .-prefixed).
                // A sub-folder inside an already-flat PageType can only be a PageCollection,
                // so if the sidecar is missing (folder created by hand in Finder, or pre-existing
                // before adoption), write a fresh one in place. Best-effort: a write failure
                // falls through to the existing nil-skip behavior.
                let parentPropertyIDs = pageType.properties.map(\.id)
                let cols = try Filesystem.childFolders(of: folder)
                    .filter { !$0.lastPathComponent.hasPrefix("_") }
                    .filter { !$0.lastPathComponent.hasPrefix(".") }
                    .compactMap { sub -> PageCollection? in
                        let collMetaURL = sub.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
                        if !Filesystem.fileExists(at: collMetaURL) {
                            let fresh = PageCollection(
                                id: ULID.generate(),
                                typeID: pageType.id,
                                title: sub.lastPathComponent,
                                folderURL: sub,
                                modifiedAt: Date()
                            )
                            try? Filesystem.writeMetadataIntoExistingFolder(
                                metadataURL: collMetaURL, metadata: fresh
                            )
                        }
                        guard var collection = try? PageCollection.load(from: collMetaURL) else {
                            return nil
                        }
                        // Heal a drifted `type_id`: the containing folder is authoritative,
                        // so a collection inside this PageType's folder belongs to it. A vault
                        // re-adoption can mint a new vault id while the collection keeps the
                        // old one — leaving it pointed at a vanished Type (empty Edit
                        // Properties pane). Re-point + re-save in place; idempotent, and
                        // mirrors the missing-sidecar / empty-views heal-on-load above.
                        if collection.typeID != pageType.id {
                            collection.typeID = pageType.id
                            try? collection.save(to: collMetaURL)
                        }
                        // Default-view migration on the Collection. Each
                        // Collection is INDEPENDENT (locked decision) — its
                        // own default Table seeded with the parent's
                        // visible-property ordering as the starting set.
                        if collection.views.isEmpty {
                            collection.views = [
                                SavedView.defaultTable(visiblePropertyIDs: parentPropertyIDs)
                            ]
                            try? collection.save(to: collMetaURL)
                        }
                        return collection
                    }
                loadedCols[pageType.id] = OrderResolver.resolve(
                    cols,
                    persistedOrder: pageType.collectionOrder,
                    titleKeyPath: \PageCollection.title
                )
            }

            self.types = OrderResolver.resolve(
                loadedTypes,
                persistedOrder: readPersistedPageTypeOrder(),
                titleKeyPath: \PageType.title
            )
            self.pageCollectionsByType = loadedCols
            self.pendingError = nil

            // Defensive index sync. The architecture's quiet contract is "DB
            // stays in sync via incremental CRUD upserts after IndexBuilder
            // runs once." That contract breaks when entities arrive outside
            // CRUD (adopted folders, externally-added folders, post-adoption
            // state, etc.) — subsequent updatePage / createPage call sites
            // pass vault.id / collection.id that aren't in the DB and FK
            // constraints fire. INSERT OR REPLACE makes this loop idempotent;
            // zero harm if a row's already there. Failures swallowed: index
            // is regeneratable, no user data lost.
            if let updater = indexUpdater {
                for pageType in self.types {
                    try? updater.upsertPageType(pageType)
                    for collection in self.pageCollectionsByType[pageType.id] ?? [] {
                        try? updater.upsertPageCollection(collection)
                    }
                }
            }
        } catch {
            self.types = []
            self.pageCollectionsByType = [:]
            self.pendingError = error
        }
    }

    // MARK: - PageType CRUD

    @discardableResult
    func createPageType(name: String, icon: String?) async throws -> PageType {
        do {
            try PageTypeValidator.validate(title: name, existing: types)

            let pageType = PageType(
                id: ULID.generate(),
                title: name,
                icon: icon,
                properties: [],
                views: [],
                modifiedAt: Date()
            )
            let folder = NexusPaths.vaultFolderURL(forTitle: name, in: nexus)
            let meta = NexusPaths.vaultMetadataURL(forTitle: name, in: nexus)
            try Filesystem.createFolderWithMetadata(folderURL: folder, metadataURL: meta, metadata: pageType)

            if let updater = indexUpdater {
                do { try updater.upsertPageType(pageType) } catch { self.pendingError = error }
            }

            types.append(pageType)
            pageCollectionsByType[pageType.id] = []
            types = OrderResolver.resolve(
                types,
                persistedOrder: readPersistedPageTypeOrder(),
                titleKeyPath: \PageType.title
            )
            return pageType
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renamePageType(_ pageType: PageType, to newName: String) async throws {
        do {
            try PageTypeValidator.validate(title: newName, existing: types, excluding: pageType)

            let oldFolder = NexusPaths.vaultFolderURL(forTitle: pageType.title, in: nexus)
            let newFolder = NexusPaths.vaultFolderURL(forTitle: newName, in: nexus)
            try Filesystem.renameFolder(from: oldFolder, to: newFolder)

            var updated = pageType
            updated.title = newName
            updated.modifiedAt = Date()
            let newMeta = NexusPaths.vaultMetadataURL(forTitle: newName, in: nexus)
            do {
                try updated.save(to: newMeta)
            } catch let saveError {
                // Roll back folder rename. Per spec: do NOT touch
                // collectionsByType here — in-memory rebuild only runs on the
                // save-success branch below.
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
                do { try updater.upsertPageType(updated) } catch { self.pendingError = error }
            }

            if let i = types.firstIndex(where: { $0.id == pageType.id }) {
                types[i] = updated
                // Rebuild PageCollection in-memory under new parent path (id + type_id unchanged;
                // schema sidecar moved with its folder, just re-derive folderURL).
                // Preserve pageOrder so a Page Type rename doesn't drop persisted ordering.
                if let oldCols = pageCollectionsByType[pageType.id] {
                    let rebuilt = oldCols.map { c -> PageCollection in
                        let newCollURL = newFolder.appendingPathComponent(c.title, isDirectory: true)
                        return PageCollection(
                            id: c.id,
                            typeID: c.typeID,
                            title: c.title,
                            folderURL: newCollURL,
                            modifiedAt: c.modifiedAt,
                            pageOrder: c.pageOrder
                        )
                    }
                    pageCollectionsByType[pageType.id] = rebuilt
                }
                types = OrderResolver.resolve(
                    types,
                    persistedOrder: readPersistedPageTypeOrder(),
                    titleKeyPath: \PageType.title
                )
            }
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func updatePageTypeIcon(_ pageType: PageType, to icon: String?) async throws {
        do {
            var updated = pageType
            updated.icon = icon
            updated.modifiedAt = Date()
            let meta = NexusPaths.vaultMetadataURL(forTitle: pageType.title, in: nexus)
            try updated.save(to: meta)
            if let updater = indexUpdater {
                do { try updater.upsertPageType(updated) } catch { self.pendingError = error }
            }
            if let i = types.firstIndex(where: { $0.id == pageType.id }) {
                types[i] = updated
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func updatePageCollectionIcon(_ collection: PageCollection, to icon: String?) async throws {
        do {
            var updated = collection
            updated.icon = icon
            updated.modifiedAt = Date()
            let metaURL = collection.folderURL
                .appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
            try updated.save(to: metaURL)
            if let updater = indexUpdater {
                do { try updater.upsertPageCollection(updated) } catch { self.pendingError = error }
            }
            var arr = pageCollectionsByType[collection.typeID] ?? []
            if let i = arr.firstIndex(where: { $0.id == collection.id }) {
                arr[i] = updated
            }
            pageCollectionsByType[collection.typeID] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func deletePageType(_ pageType: PageType) async throws {
        do {
            let folder = NexusPaths.vaultFolderURL(forTitle: pageType.title, in: nexus)
            try Filesystem.moveToTrash(folder, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deletePageType(id: pageType.id) } catch { self.pendingError = error }
            }
            types.removeAll { $0.id == pageType.id }
            pageCollectionsByType.removeValue(forKey: pageType.id)
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - PageCollection CRUD

    @discardableResult
    func createPageCollection(name: String, inPageType pageType: PageType) async throws -> PageCollection {
        do {
            let existing = pageCollectionsByType[pageType.id] ?? []
            try PageCollectionValidator.validate(title: name, existingInType: existing)

            let folder = NexusPaths.collectionFolderURL(
                forTitle: name, inVaultTitled: pageType.title, in: nexus
            )
            let now = Date()
            let coll = PageCollection(
                id: ULID.generate(),
                typeID: pageType.id,
                title: name,
                folderURL: folder,
                modifiedAt: now
            )
            let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
            try Filesystem.createFolderWithMetadata(
                folderURL: folder, metadataURL: metaURL, metadata: coll
            )

            if let updater = indexUpdater {
                do { try updater.upsertPageCollection(coll) } catch { self.pendingError = error }
            }

            var arr = existing
            arr.append(coll)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: pageType.collectionOrder,
                titleKeyPath: \PageCollection.title
            )
            pageCollectionsByType[pageType.id] = arr
            return coll
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renamePageCollection(_ collection: PageCollection, to newName: String) async throws {
        do {
            guard let pageType = types.first(where: { $0.id == collection.typeID }) else { return }
            let existing = pageCollectionsByType[pageType.id] ?? []
            try PageCollectionValidator.validate(
                title: newName, existingInType: existing, excluding: collection
            )

            let newURL = NexusPaths.collectionFolderURL(
                forTitle: newName, inVaultTitled: pageType.title, in: nexus
            )
            try Filesystem.renameFolder(from: collection.folderURL, to: newURL)

            // Bump modified_at in the sidecar at its new location. Preserve
            // pageOrder so a rename doesn't drop persisted ordering.
            let now = Date()
            let updated = PageCollection(
                id: collection.id,
                typeID: collection.typeID,
                title: newName,
                folderURL: newURL,
                modifiedAt: now,
                pageOrder: collection.pageOrder
            )
            let metaURL = newURL.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
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
                do { try updater.upsertPageCollection(updated) } catch { self.pendingError = error }
            }

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == collection.id }) {
                arr[i] = updated
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: pageType.collectionOrder,
                    titleKeyPath: \PageCollection.title
                )
            }
            pageCollectionsByType[pageType.id] = arr
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func deletePageCollection(_ collection: PageCollection) async throws {
        do {
            try Filesystem.moveToTrash(collection.folderURL, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deletePageCollection(id: collection.id) } catch { self.pendingError = error }
            }
            var arr = pageCollectionsByType[collection.typeID] ?? []
            arr.removeAll { $0.id == collection.id }
            pageCollectionsByType[collection.typeID] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Reorders Page Types in response to a sidebar drag (v0.2.8.0). Matches the
    /// SwiftUI `.onMove(perform:)` signature. New full ID order persists to
    /// `.nexus/state.json`.
    func reorderPageTypes(fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = types
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != types else { return }
        types = arr
        do {
            try OrderPersister.setVaultOrder(arr.map(\.id), in: nexus)
        } catch {
            self.pendingError = error
        }
    }

    /// Reorders PageCollections within `pageType`. New ID order persists to the parent
    /// Page Type's schema sidecar.
    func reorderPageCollections(in pageType: PageType, fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = pageCollectionsByType[pageType.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        pageCollectionsByType[pageType.id] = arr
        do {
            try OrderPersister.setPageCollectionOrder(arr.map(\.id), in: pageType, nexus: nexus)
            // Keep the in-memory PageType's collectionOrder in sync.
            if let i = types.firstIndex(where: { $0.id == pageType.id }) {
                types[i].collectionOrder = arr.map(\.id)
            }
        } catch {
            self.pendingError = error
        }
    }

    /// Reads the persisted Page Type sibling order from `.nexus/state.json`. Returns
    /// nil if no state.json exists or no `vault_order` has been recorded — the
    /// resolver falls back to alphabetic in that case.
    private func readPersistedPageTypeOrder() -> [String]? {
        let url = NexusPaths.nexusStateURL(in: nexus)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (try? AtomicJSON.decode(NexusState.self, from: url))?.vaultOrder
    }

}

// MARK: - Schema CRUD errors

enum PageTypeManagerError: Error, Equatable {
    case typeNotFound
    case propertyNotFound
    case lossyChangeRequiresConfirmation
    case indexOutOfBounds
}

/// Human-readable text so these errors render as a friendly sentence instead of
/// the raw bridged enum name ("Pommora.PageTypeManagerError error N"). Delegates
/// to `PropertyEditorErrorMessage` (the popover banner's mapper) so the two
/// surfaces stay in lockstep from a single source of truth.
extension PageTypeManagerError: LocalizedError {
    var errorDescription: String? { PropertyEditorErrorMessage.string(for: self) }
}

// MARK: - Schema CRUD methods

extension PageTypeManager {

    // MARK: - Add property

    /// Adds a property definition to a Page Type's schema. If `definition.id` is empty,
    /// a new user-property ID (`prop_<ulid>`) is minted. Validates against existing
    /// properties via `PropertyDefinitionValidator`. Schema-only write (member files
    /// are not touched — identity is stored by ID).
    ///
    /// **Paired relations** (`definition.type == .relation && definition.dualProperty != nil`):
    /// Routed through `DualRelationCoordinator.createPairedRelation` which writes both
    /// Type sidecars atomically. The authoritative target kind+id is `definition.relationTarget`;
    /// the target `TypeKind` is resolved from it: same-side PageType from in-memory `types`,
    /// cross-side ItemType + Agenda singletons from disk. `definition.reverseName` carries the
    /// reverse property display name (caller convention at add-time); the coordinator mints the
    /// reverse property and writes its ID into `dualProperty.syncedPropertyID` after creation.
    /// Collection / context-tier targets reject dual pairing.
    func addProperty(_ definition: PropertyDefinition, to typeID: String) async throws {
        do { try PerTypeSchemaService.addProperty(definition, in: typeID, on: schemaAdapter) } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Resolves a paired-relation's target `DualRelationCoordinator.TypeKind` from
    /// its `RelationTarget`. Same-side PageType reads in-memory `types`; cross-side
    /// ItemType + Agenda singletons load from disk (they live outside this manager).
    /// Collection / context-tier targets never carry a `dualProperty` in practice —
    /// they throw here (context-tier is additionally rejected inside the coordinator).
    private func resolveDualTargetKind(
        for scope: PropertyDefinition.RelationTarget
    ) throws -> DualRelationCoordinator.TypeKind {
        switch scope {
        case .pageType(let id):
            guard let pt = types.first(where: { $0.id == id }) else {
                throw PageTypeManagerError.typeNotFound
            }
            return .pageType(pt)
        case .itemType(let id):
            guard let it = ItemType.find(id: id, in: nexus) else {
                throw PageTypeManagerError.typeNotFound
            }
            return .itemType(it)
        case .agendaTasks:
            let schema = try AtomicJSON.decode(
                AgendaTaskSchema.self, from: NexusPaths.taskSchemaURL(in: nexus))
            return .agendaTasks(schema)
        case .agendaEvents:
            let schema = try AtomicJSON.decode(
                AgendaEventSchema.self, from: NexusPaths.eventSchemaURL(in: nexus))
            return .agendaEvents(schema)
        case .pageCollection, .itemCollection, .contextTier:
            // Collections are legacy / not user-creatable; context-tier carries no
            // dualProperty. None reaches a dual-pair create in practice.
            throw PageTypeManagerError.propertyNotFound
        }
    }

    // MARK: - Update paired relation (reverse/mirror side)

    /// Updates ONLY the reverse (mirror) side of a paired relation; the home
    /// side is edited separately via `renameProperty` / the icon transform. Reads
    /// the current home name/icon (passed through unchanged) and routes both sides
    /// through `DualRelationCoordinator.updatePairedRelation` (F3), then reloads
    /// both Types into memory. Mirror of `addProperty`'s paired branch.
    func updatePairedRelation(
        propertyID: String, newReverseName: String, newReverseIcon: String?, in typeID: String
    ) async throws {
        do {
            guard let i = types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            guard let def = types[i].properties.first(where: { $0.id == propertyID }),
                def.type == .relation, def.dualProperty != nil,
                let scope = def.relationTarget
            else {
                throw PageTypeManagerError.propertyNotFound
            }
            let sourceKind = DualRelationCoordinator.TypeKind.pageType(types[i])
            let targetKind = try resolveDualTargetKind(for: scope)
            try DualRelationCoordinator.updatePairedRelation(
                sourcePropertyID: propertyID,
                sourceKind: sourceKind,
                targetKind: targetKind,
                newHomeName: def.name,
                newHomeIcon: def.icon,
                newReverseName: newReverseName,
                newReverseIcon: newReverseIcon,
                nexus: nexus
            )
            // Reload both sides into memory so live views reflect the atomic sidecar
            // write. Same-manager target reloads inline; a cross-manager (ItemType)
            // target routes through the injected hook. No re-index: the reverse
            // name/icon are display-only and the index is regeneratable (relation
            // VALUES key on ID), so the in-memory reload keeps every view correct.
            let meta = NexusPaths.vaultMetadataURL(forTitle: types[i].title, in: nexus)
            if let reloaded = try? PageType.load(from: meta) {
                types[i] = reloaded
            }
            let targetID = targetKind.typeID
            if targetID != typeID {
                if let j = types.firstIndex(where: { $0.id == targetID }) {
                    let targetMeta = NexusPaths.vaultMetadataURL(forTitle: types[j].title, in: nexus)
                    if let reloaded = try? PageType.load(from: targetMeta) {
                        types[j] = reloaded
                    }
                } else {
                    reloadTypeByID?(targetID)
                }
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Rename property

    /// Renames a property by its stable ID. Schema-only write — member files keyed by
    /// `id` are not touched (rename-safe by design per the domain model).
    func renameProperty(id propertyID: String, in typeID: String, to newName: String) async throws {
        do { try PerTypeSchemaService.renameProperty(id: propertyID, in: typeID, to: newName, on: schemaAdapter) } catch
        {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Delete property

    /// Deletes a property from the schema. Atomically removes the schema entry and
    /// strips the corresponding key from every member Page's frontmatter
    /// `properties` dictionary via `SchemaTransaction`.
    ///
    /// **Paired relations** (`property.dualProperty != nil`): routed through
    /// `DualRelationCoordinator.deletePair` which cascades the delete to both
    /// Type sidecars and strips all values from member files on each side.
    // MARK: - Update view (per-container SavedView edit)

    /// Apply a transform to a SavedView on a PageType or PageCollection
    /// container (looked up by container ID), then persist the parent
    /// sidecar atomically. Used by the View Settings Property Visibility
    /// pane (Task 12) to write the visibleProperties / hiddenProperties
    /// edits live as the user toggles + drag-reorders rows.
    ///
    /// `containerID` may be either a PageType.id or a PageCollection.id —
    /// we search both. Throws if neither resolves or the view isn't found.
    func updateView(
        _ viewID: String,
        in containerID: String,
        transform: (inout SavedView) -> Void
    ) async throws {
        do {
            // Try PageType first.
            if let i = types.firstIndex(where: { $0.id == containerID }) {
                guard let vi = types[i].views.firstIndex(where: { $0.id == viewID }) else {
                    throw PageTypeManagerError.propertyNotFound
                }
                var updated = types[i]
                transform(&updated.views[vi])
                updated.modifiedAt = Date()
                let meta = NexusPaths.vaultMetadataURL(forTitle: updated.title, in: nexus)
                try updated.save(to: meta)
                types[i] = updated
                return
            }
            // Else PageCollection lookup.
            for (typeID, cols) in pageCollectionsByType {
                if let ci = cols.firstIndex(where: { $0.id == containerID }) {
                    var coll = cols[ci]
                    guard let vi = coll.views.firstIndex(where: { $0.id == viewID }) else {
                        throw PageTypeManagerError.propertyNotFound
                    }
                    transform(&coll.views[vi])
                    coll.modifiedAt = Date()
                    let meta = coll.folderURL.appendingPathComponent(
                        NexusPaths.pageCollectionSidecarFilename
                    )
                    try coll.save(to: meta)
                    pageCollectionsByType[typeID]?[ci] = coll
                    return
                }
            }
            throw PageTypeManagerError.typeNotFound
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Duplicate property

    /// Deep-copy a PropertyDefinition: mint a new ULID, copy every per-type
    /// config field, append "(copy)" to the display name, and append to the
    /// owning Type's schema. Member Page files are NOT touched (per locked
    /// rule: "add property = schema-only write" — new copies start empty
    /// on every member entity, ready to fill).
    ///
    /// Paired-relation duplicates: the dualProperty config is preserved but
    /// each duplicate is paired anew with the existing target — this is
    /// effectively "create another relation to the same target Type."
    /// SchemaTransaction handles the atomic write across both sides.
    /// At v0.3.1 we keep this case simple — duplicate skips the relation
    /// dual-pair re-creation and just adds the non-relation fields fresh.
    /// Relation dup is flagged for v0.3.1.5 follow-up.
    func duplicateProperty(id propertyID: String, in typeID: String) async throws {
        do {
            guard let i = types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            guard let j = types[i].properties.firstIndex(where: { $0.id == propertyID }) else {
                throw PageTypeManagerError.propertyNotFound
            }

            var duplicated = types[i].properties[j]
            duplicated.id = ReservedPropertyID.mintUserPropertyID()
            duplicated.name = "\(duplicated.name) (copy)"
            duplicated.dualProperty = nil  // Defer relation dup re-pairing to v0.3.1.5.

            try PropertyDefinitionValidator.validate(
                duplicated, in: types[i].properties, nexus: NexusContext.forTypeResolution(in: nexus))

            var updatedType = types[i]
            updatedType.properties.append(duplicated)
            updatedType.modifiedAt = Date()

            let meta = NexusPaths.vaultMetadataURL(forTitle: updatedType.title, in: nexus)
            try updatedType.save(to: meta)

            if let updater = indexUpdater {
                let position = updatedType.properties.count - 1
                do {
                    try updater.upsertPropertyDefinition(
                        duplicated, owningTypeID: typeID, owningTypeKind: "page_type", position: position
                    )
                } catch { self.pendingError = error }
            }

            types[i] = updatedType
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Update property (transform-based per-config edit)

    /// Apply an in-place transform to a PropertyDefinition's per-config
    /// fields. Validates against the rest of the schema, persists the
    /// parent PageType sidecar atomically, and upserts into the SQLite
    /// index. Used by the View Settings Edit Property pane (Task 11) to
    /// live-save option-list / displayAs / dateFormat / numberFormat /
    /// accept / icon changes without bespoke per-field manager methods.
    func updateProperty(
        id propertyID: String,
        in typeID: String,
        transform: (inout PropertyDefinition) -> Void
    ) async throws {
        do {
            guard let i = types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            guard let j = types[i].properties.firstIndex(where: { $0.id == propertyID }) else {
                throw PageTypeManagerError.propertyNotFound
            }

            var updatedDef = types[i].properties[j]
            transform(&updatedDef)

            var siblings = types[i].properties
            siblings.remove(at: j)
            try PropertyDefinitionValidator.validate(
                updatedDef, in: siblings, nexus: NexusContext.forTypeResolution(in: nexus))

            var updatedType = types[i]
            updatedType.properties[j] = updatedDef
            updatedType.modifiedAt = Date()

            let meta = NexusPaths.vaultMetadataURL(forTitle: updatedType.title, in: nexus)
            try updatedType.save(to: meta)

            if let updater = indexUpdater {
                do {
                    try updater.upsertPropertyDefinition(
                        updatedDef, owningTypeID: typeID, owningTypeKind: "page_type", position: j
                    )
                } catch { self.pendingError = error }
            }

            types[i] = updatedType
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func deleteProperty(id propertyID: String, in typeID: String) async throws {
        do { try PerTypeSchemaService.deleteProperty(id: propertyID, in: typeID, on: schemaAdapter) } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Reorder property

    /// Moves a property to a new index within the schema's `properties` array.
    /// Schema-only write — member files are not touched.
    func reorderProperty(id propertyID: String, in typeID: String, toIndex newIndex: Int) async throws {
        do {
            try PerTypeSchemaService.reorderProperty(id: propertyID, in: typeID, toIndex: newIndex, on: schemaAdapter)
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
    ///   strips the property's value from every member Page's frontmatter via
    ///   `SchemaTransaction`.
    func changeType(
        of propertyID: String,
        in typeID: String,
        to newType: PropertyType,
        dropConflictingValues: Bool = false
    ) async throws {
        do {
            try PerTypeSchemaService.changeType(
                of: propertyID,
                in: typeID,
                to: newType,
                dropConflictingValues: dropConflictingValues,
                on: schemaAdapter)
        } catch {
            self.pendingError = error
            throw error
        }
    }
}

// MARK: - Per-type schema adapter

extension PageTypeManager {

    /// Once-constructed adapter that supplies the Page-side per-side bits to the
    /// shared `PerTypeSchemaService`. Constructed lazily so `self` is fully
    /// initialized before the `unowned` back-reference is captured.
    fileprivate var schemaAdapter: PageSchemaAdapter {
        if let existing = _schemaAdapter { return existing }
        let adapter = PageSchemaAdapter(self)
        _schemaAdapter = adapter
        return adapter
    }

    /// Bridges `PageTypeManager`'s in-memory `types` + `_pagetype.json` sidecars to
    /// `PerTypeSchemaService`. Reproduces the original five method bodies' per-side
    /// Page behavior verbatim. `unowned` because the manager owns the adapter for its
    /// full lifetime.
    fileprivate final class PageSchemaAdapter: PerTypeSchemaAdapter {
        unowned let m: PageTypeManager
        /// Holds the type staged by `stageType` so `commitStagedType` assigns the
        /// byte-identical value (same `modifiedAt`) to `m.types[i]` — matching the
        /// original's single `updated` computed once and reused across the staged
        /// sidecar and the post-commit in-memory assign.
        private var stagedType: PageType?

        init(_ m: PageTypeManager) { self.m = m }

        // MARK: Type / schema read

        func properties(forTypeID typeID: String) throws -> [PropertyDefinition] {
            guard let pt = m.types.first(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            return pt.properties
        }

        // MARK: Schema persist

        func commitType(properties: [PropertyDefinition], forTypeID typeID: String) throws {
            guard let i = m.types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            var updated = m.types[i]
            updated.properties = properties
            updated.modifiedAt = Date()
            try updated.save(to: NexusPaths.vaultMetadataURL(forTitle: updated.title, in: m.nexus))
            m.types[i] = updated
        }

        func stageType(
            properties: [PropertyDefinition], forTypeID typeID: String, into tx: SchemaTransaction
        ) throws {
            guard let i = m.types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            var updated = m.types[i]
            updated.properties = properties
            updated.modifiedAt = Date()
            try tx.stage(updated, to: NexusPaths.vaultMetadataURL(forTitle: updated.title, in: m.nexus))
            stagedType = updated
        }

        func commitStagedType(forTypeID typeID: String) {
            guard let updated = stagedType,
                let i = m.types.firstIndex(where: { $0.id == typeID })
            else { return }
            m.types[i] = updated
            stagedType = nil
        }

        // MARK: Paired-relation collaborators

        func typeKind(forTypeID typeID: String) throws -> DualRelationCoordinator.TypeKind {
            guard let pt = m.types.first(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            return .pageType(pt)
        }

        func reverseRelationTarget(forTypeID typeID: String) -> PropertyDefinition.RelationTarget {
            .pageType(typeID)
        }

        func resolveDualTargetKind(
            for scope: PropertyDefinition.RelationTarget
        ) throws -> DualRelationCoordinator.TypeKind {
            try m.resolveDualTargetKind(for: scope)
        }

        func reloadType(byID typeID: String) {
            // Same-side (a PageType this manager owns) reloads from disk inline;
            // cross-manager targets route through the injected `reloadTypeByID?` hook.
            if let i = m.types.firstIndex(where: { $0.id == typeID }) {
                let meta = NexusPaths.vaultMetadataURL(forTitle: m.types[i].title, in: m.nexus)
                if let reloaded = try? PageType.load(from: meta) {
                    m.types[i] = reloaded
                }
            } else {
                m.reloadTypeByID?(typeID)
            }
        }

        var nexusForCoordinator: Nexus { m.nexus }

        // MARK: Member files

        func memberFiles(forTypeID typeID: String) throws -> [URL] {
            guard let pt = m.types.first(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            let typeFolder = NexusPaths.vaultFolderURL(forTitle: pt.title, in: m.nexus)
            return try Filesystem.descendantFiles(of: typeFolder) { url in
                url.pathExtension == "md"
            }
        }

        func stripPropertyFromMembers(
            _ propertyID: String, forTypeID typeID: String, into tx: SchemaTransaction
        ) throws {
            let pageFiles = try memberFiles(forTypeID: typeID)
            MemberFileStrip.forEach(pageFiles) { pageURL in
                var (fm, body) = try AtomicYAMLMarkdown.load(PageFrontmatter.self, from: pageURL)
                guard fm.properties[propertyID] != nil else { return }
                fm.properties.removeValue(forKey: propertyID)
                let data = try AtomicYAMLMarkdown.encode(frontmatter: fm, body: body)
                tx.stage(payload: data, to: pageURL)
            }
        }

        // MARK: Index

        var indexOwningTypeKind: String { "page_type" }
        var indexUpdater: IndexUpdater? { m.indexUpdater }

        // MARK: Validation

        var validationContext: NexusContext { NexusContext.forTypeResolution(in: m.nexus) }

        // MARK: Errors

        var errTypeNotFound: any Error { PageTypeManagerError.typeNotFound }
        var errPropertyNotFound: any Error { PageTypeManagerError.propertyNotFound }
        var errLossyChangeRequiresConfirmation: any Error {
            PageTypeManagerError.lossyChangeRequiresConfirmation
        }
        var errIndexOutOfBounds: any Error { PageTypeManagerError.indexOutOfBounds }

        // MARK: pendingError sink

        func recordIndexError(_ error: any Error) { m.pendingError = error }
    }
}
