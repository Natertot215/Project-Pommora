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

    /// Fired after a rename moves a PageCollection's folder on disk (its own
    /// rename, or its parent Page Type's) with the updated collection.
    /// NexusEnvironment wires this to PageSetManager.rebuildFolderURLs so
    /// cached child-Set URLs follow the move. Optional — no-op when unset.
    var onCollectionFolderChanged: (@MainActor (PageCollection) -> Void)?

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

    /// The saved views on a view-bearing container, looked up by id across BOTH
    /// PageTypes and PageCollections. The single source for the dual-container
    /// `[SavedView]` lookup the View Settings panes + Views dropdown all need;
    /// `ActiveViewStore.resolvedActiveView(in:manager:)` builds on it to resolve
    /// the active view. Empty when the id matches no container.
    func views(in containerID: String) -> [SavedView] {
        if let t = types.first(where: { $0.id == containerID }) { return t.views }
        for cols in pageCollectionsByType.values {
            if let c = cols.first(where: { $0.id == containerID }) { return c.views }
        }
        return []
    }

    /// Reloads a single PageType from disk into the in-memory `types` array by ID.
    /// No-op if the ID isn't one of this manager's types (the cross-manager router
    /// only dispatches IDs it has already matched to this manager). Best-effort: a
    /// load failure leaves the stale in-memory copy in place (disk is canonical; a
    /// later loadAll converges).
    func reloadTypeFromDisk(id: String) {
        guard let i = types.firstIndex(where: { $0.id == id }) else { return }
        let meta = NexusPaths.vaultMetadataURL(forTitle: types[i].title, in: nexus)
        if let reloaded = try? PageType.load(from: meta) {
            types[i] = reloaded
        }
    }

    /// Runs `body`, recording any thrown error in `pendingError` (so the error
    /// toast fires) before rethrowing. `skipIf` suppresses the record for an error
    /// a method already surfaced itself (the rename rollback's `RenameAtomicityError`).
    private func withPendingError<T>(
        skipIf: (any Error) -> Bool = { _ in false },
        _ body: () throws -> T
    ) throws -> T {
        do {
            return try body()
        } catch {
            if !skipIf(error) { pendingError = error }
            throw error
        }
    }

    // MARK: - Load

    func loadAll(filter: FolderFilter = .empty) async {
        do {
            // flatlayout: PageType folders sit at the Nexus root. Discovery
            // filters folders by presence of `_pagetype.json`; folders carrying
            // any of the other per-kind sidecars (Agenda/Collection) or
            // no recognized sidecar are skipped. NexusAdopter is the single
            // canonical migration surface — it surfaces unrecognized / legacy
            // folders to the user via the preview sheet on launch. No in-loader
            // auto-heal here (would race the adopter and produce inconsistent
            // state).
            let root = nexus.rootURL

            let topLevel = try Filesystem.childFolders(of: root, folderFilter: filter)
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .filter { !$0.lastPathComponent.hasPrefix("_") }

            var typeFolders: [URL] = []
            var loadedTypes: [PageType] = []

            for folder in topLevel {
                let metaURL = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
                guard Filesystem.fileExists(at: metaURL),
                    var pageType = try? PageType.load(from: metaURL)
                else { continue }

                // Default-view migration: if the PageType has no saved views,
                // mint a Table view exposing every user-defined property as a
                // column. Idempotent — the `views.isEmpty` gate is the only
                // mutation trigger. Best-effort: failures fall through and the
                // next loadAll retries (no user data lost).
                if pageType.views.isEmpty {
                    pageType.views = [
                        SavedView.defaultTable(
                            visiblePropertyIDs: pageType.properties.map(\.id),
                            defaultSort: pageType.defaultSort
                        )
                    ]
                    try? pageType.save(to: metaURL)
                }
                typeFolders.append(folder)
                loadedTypes.append(pageType)
            }

            // Duplicate-ULID heal: a Finder-duplicated Type folder clones the
            // `_pagetype.json` id. Runs BEFORE collection discovery so the
            // `typeID` drift-heal below re-points the duplicate's collections
            // at the freshly-minted id in the same pass.
            var seenTypeIDs: Set<String> = []
            loadedTypes = ContainerIDHealer.heal(
                loadedTypes, seen: &seenTypeIDs,
                reID: { $0.id = ULID.generate() },
                save: { try $0.save(to: NexusPaths.vaultMetadataURL(forTitle: $0.title, in: nexus)) }
            )

            var loadedCols: [String: [PageCollection]] = [:]
            // Load-wide id namespace — also catches collection ids cloned
            // ACROSS two Types when a whole Type folder was duplicated.
            var seenCollectionIDs: Set<String> = []

            for (folder, pageType) in zip(typeFolders, loadedTypes) {
                // Discover PageCollections (sub-folders with `_pagecollection.json`; skip _- and .-prefixed).
                // A sub-folder inside an already-flat PageType can only be a PageCollection,
                // so if the sidecar is missing (folder created by hand in Finder, or pre-existing
                // before adoption), write a fresh one in place. Best-effort: a write failure
                // falls through to the existing nil-skip behavior.
                let parentPropertyIDs = pageType.properties.map(\.id)
                var cols = try Filesystem.childFolders(of: folder, folderFilter: filter)
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
                                SavedView.defaultTable(
                                    visiblePropertyIDs: parentPropertyIDs,
                                    defaultSort: pageType.defaultSort
                                )
                            ]
                            try? collection.save(to: collMetaURL)
                        }
                        return collection
                    }
                // Duplicate-ULID heal: a Finder-duplicated Collection folder
                // clones the `_pagecollection.json` id. Runs before the
                // defensive index upsert so two rows never share one id.
                cols = ContainerIDHealer.heal(
                    cols, seen: &seenCollectionIDs,
                    reID: { $0.id = ULID.generate() },
                    save: {
                        try $0.save(
                            to: $0.folderURL.appendingPathComponent(
                                NexusPaths.pageCollectionSidecarFilename))
                    }
                )
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
        return try withPendingError {
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
        }
    }

    func renamePageType(_ pageType: PageType, to newName: String) async throws {
        try withPendingError(skipIf: { $0 is RenameAtomicityError }) {
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
                    rebuilt.forEach { onCollectionFolderChanged?($0) }
                }
                types = OrderResolver.resolve(
                    types,
                    persistedOrder: readPersistedPageTypeOrder(),
                    titleKeyPath: \PageType.title
                )
            }
        }
    }

    func updatePageTypeIcon(_ pageType: PageType, to icon: String?) async throws {
        try withPendingError {
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
        }
    }

    func updatePageCollectionIcon(_ collection: PageCollection, to icon: String?) async throws {
        try withPendingError {
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
        }
    }

    func deletePageType(_ pageType: PageType) async throws {
        try withPendingError {
            let folder = NexusPaths.vaultFolderURL(forTitle: pageType.title, in: nexus)
            try Filesystem.moveToTrash(folder, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deletePageType(id: pageType.id) } catch { self.pendingError = error }
            }
            types.removeAll { $0.id == pageType.id }
            pageCollectionsByType.removeValue(forKey: pageType.id)
        }
    }

    // MARK: - PageCollection CRUD

    @discardableResult
    func createPageCollection(name: String, inPageType pageType: PageType) async throws -> PageCollection {
        return try withPendingError {
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
        }
    }

    func renamePageCollection(_ collection: PageCollection, to newName: String) async throws {
        try withPendingError(skipIf: { $0 is RenameAtomicityError }) {
            guard let pageType = types.first(where: { $0.id == collection.typeID }) else { return }
            let existing = pageCollectionsByType[pageType.id] ?? []
            try PageCollectionValidator.validate(
                title: newName, existingInType: existing, excluding: collection
            )

            let newURL = NexusPaths.collectionFolderURL(
                forTitle: newName, inVaultTitled: pageType.title, in: nexus
            )
            try Filesystem.renameFolder(from: collection.folderURL, to: newURL)

            // Copy-mutate so a rename only touches what a rename legitimately
            // changes (title / folderURL / modifiedAt) and preserves every other
            // field — icon, views, schemaVersion, pageOrder, and any future
            // field — automatically.
            let now = Date()
            var updated = collection
            updated.title = newName
            updated.folderURL = newURL
            updated.modifiedAt = now
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
            onCollectionFolderChanged?(updated)
        }
    }

    func deletePageCollection(_ collection: PageCollection) async throws {
        try withPendingError {
            try Filesystem.moveToTrash(collection.folderURL, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deletePageCollection(id: collection.id) } catch { self.pendingError = error }
            }
            var arr = pageCollectionsByType[collection.typeID] ?? []
            arr.removeAll { $0.id == collection.id }
            pageCollectionsByType[collection.typeID] = arr
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

    // MARK: - Open-in

    /// Persists the vault-level default for how Pages open (`open_in` on the
    /// `_pagetype.json` sidecar): `.compact` (PagePreview card) or `.window`
    /// (main detail pane). No SQLite upsert — `open_in` is not indexed.
    func setOpenIn(_ mode: OpenInMode, forVault typeID: String) async throws {
        guard let i = types.firstIndex(where: { $0.id == typeID }) else {
            throw PageTypeManagerError.typeNotFound
        }
        var updated = types[i]
        updated.openIn = mode
        updated.modifiedAt = Date()
        try withPendingError {
            try updated.save(to: NexusPaths.vaultMetadataURL(forTitle: updated.title, in: nexus))
        }
        types[i] = updated
    }

    // MARK: - Banner

    /// Persists a container's banner image path (`banner` on the `_pagetype.json`
    /// or `_pagecollection.json` sidecar). `path` is the nexus-relative path
    /// returned by `CoverAssetStore` (or nil to clear the banner). No SQLite
    /// upsert — `banner` is not indexed.
    ///
    /// Uses the Task-3 disk read-modify-write pattern (load the sidecar FRESH,
    /// set `banner`, save, re-sync the in-memory cache) — NOT setOpenIn's
    /// in-memory-first save — so a concurrent sibling-order write to the same
    /// sidecar isn't clobbered. Handles BOTH container kinds, like `updateView`.
    func setBanner(_ path: String?, forContainer containerID: String) async throws {
        try withPendingError {
            // PageType first.
            if let i = types.firstIndex(where: { $0.id == containerID }) {
                let meta = NexusPaths.vaultMetadataURL(forTitle: types[i].title, in: nexus)
                var updated = try PageType.load(from: meta)
                updated.banner = path
                updated.modifiedAt = Date()
                try updated.save(to: meta)
                types[i] = updated
                return
            }
            // Else PageCollection lookup.
            for (typeID, cols) in pageCollectionsByType {
                if let ci = cols.firstIndex(where: { $0.id == containerID }) {
                    let meta = cols[ci].folderURL.appendingPathComponent(
                        NexusPaths.pageCollectionSidecarFilename
                    )
                    var coll = try PageCollection.load(from: meta)
                    coll.banner = path
                    coll.modifiedAt = Date()
                    try coll.save(to: meta)
                    pageCollectionsByType[typeID]?[ci] = coll
                    return
                }
            }
            throw PageTypeManagerError.typeNotFound
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
    case cannotDeleteLastView
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
    func addProperty(_ definition: PropertyDefinition, to typeID: String) async throws {
        try withPendingError {
            try PerTypeSchemaService.addProperty(definition, in: typeID, on: schemaAdapter)
        }
    }

    // MARK: - Rename property

    /// Renames a property by its stable ID. Schema-only write — member files keyed by
    /// `id` are not touched (rename-safe by design per the domain model).
    func renameProperty(id propertyID: String, in typeID: String, to newName: String) async throws {
        try withPendingError {
            try PerTypeSchemaService.renameProperty(id: propertyID, in: typeID, to: newName, on: schemaAdapter)
        }
    }

    // MARK: - Update view (per-container SavedView edit)

    /// Apply a transform to a SavedView on a PageType or PageCollection
    /// container (looked up by container ID), then persist the parent
    /// sidecar atomically. Used by the View Settings Property Visibility
    /// pane to write the propertyOrder / hiddenProperties edits live as
    /// the user toggles + drag-reorders rows.
    ///
    /// `containerID` may be either a PageType.id or a PageCollection.id —
    /// we search both. Throws if neither resolves or the view isn't found.
    func updateView(
        _ viewID: String,
        in containerID: String,
        transform: (inout SavedView) -> Void
    ) async throws {
        // The single-view case of `mutateViews` — same fresh-from-disk
        // read-modify-atomic-write (never clobbers a concurrent `page_order`
        // sidecar write) and the same dual-container resolution, with the view
        // located by id inside the mutation. A missing view throws BEFORE any
        // save, so nothing is written.
        try await mutateViews(in: containerID) { views in
            guard let vi = views.firstIndex(where: { $0.id == viewID }) else {
                throw PageTypeManagerError.propertyNotFound
            }
            transform(&views[vi])
        }
    }

    // MARK: - View CRUD (add / duplicate / delete / rename)

    /// Read-modify-write the WHOLE `views` array on a PageType or
    /// PageCollection container (looked up by container ID), mirroring
    /// `updateView`'s fresh-from-disk disk pattern so a concurrent
    /// sidecar write (e.g. a drag-reorder's `page_order`) is never clobbered.
    ///
    /// `transform` receives the freshly-loaded `views` array `inout` and may
    /// throw (the guard cases — e.g. deleting the last view — surface here);
    /// it returns an arbitrary value handed back to the caller (the newly
    /// minted / duplicated view). When `transform` throws, nothing is written.
    private func mutateViews<Result>(
        in containerID: String,
        transform: (inout [SavedView]) throws -> Result
    ) async throws -> Result {
        return try withPendingError {
            if let i = types.firstIndex(where: { $0.id == containerID }) {
                let meta = NexusPaths.vaultMetadataURL(forTitle: types[i].title, in: nexus)
                var updated = try PageType.load(from: meta)
                let result = try transform(&updated.views)
                updated.modifiedAt = Date()
                try updated.save(to: meta)
                types[i] = updated
                return result
            }
            for (typeID, cols) in pageCollectionsByType {
                if let ci = cols.firstIndex(where: { $0.id == containerID }) {
                    let meta = cols[ci].folderURL.appendingPathComponent(
                        NexusPaths.pageCollectionSidecarFilename)
                    var coll = try PageCollection.load(from: meta)
                    let result = try transform(&coll.views)
                    coll.modifiedAt = Date()
                    try coll.save(to: meta)
                    pageCollectionsByType[typeID]?[ci] = coll
                    return result
                }
            }
            throw PageTypeManagerError.typeNotFound
        }
    }

    /// Appends a new view of `type` named "Untitled View". A `.gallery` view
    /// mints `cardSize: .medium` (the Gallery renderer's default density) with
    /// `showCover` left nil (covers hidden by default). Returns the minted view.
    @discardableResult
    func addView(type: ViewType, to containerID: String) async throws -> SavedView {
        let isGallery = type == .gallery
        let view = SavedView(
            id: "view_\(ULID.generate())",
            name: "Untitled View",
            icon: type.defaultIcon,
            type: type,
            cardSize: isGallery ? .medium : nil,
            showCover: nil)
        return try await mutateViews(in: containerID) { views in
            views.append(view)
            return view
        }
    }

    /// Deep-copies `viewID` with a FRESH id, carrying every v2 field forward,
    /// and appends it. Returns the new view.
    @discardableResult
    func duplicateView(_ viewID: String, in containerID: String) async throws -> SavedView {
        try await mutateViews(in: containerID) { views in
            guard let source = views.first(where: { $0.id == viewID }) else {
                throw PageTypeManagerError.propertyNotFound
            }
            var copy = source
            copy.id = "view_\(ULID.generate())"
            views.append(copy)
            return copy
        }
    }

    /// Removes `viewID`, guarding the ≥1-view invariant: deleting the last
    /// remaining view throws `.cannotDeleteLastView` and writes nothing.
    func deleteView(_ viewID: String, in containerID: String) async throws {
        try await mutateViews(in: containerID) { views in
            guard views.count > 1 else {
                throw PageTypeManagerError.cannotDeleteLastView
            }
            guard let idx = views.firstIndex(where: { $0.id == viewID }) else {
                throw PageTypeManagerError.propertyNotFound
            }
            views.remove(at: idx)
        }
    }

    /// Renames `viewID` in place (filename-as-title doesn't apply to views —
    /// the name lives in the sidecar's `views[i].name`).
    func renameView(_ viewID: String, in containerID: String, to newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await mutateViews(in: containerID) { views in
            guard let idx = views.firstIndex(where: { $0.id == viewID }) else {
                throw PageTypeManagerError.propertyNotFound
            }
            views[idx].name = trimmed
        }
    }

    // MARK: - Duplicate property

    /// Deep-copy a PropertyDefinition: mint a new ULID, copy every per-type
    /// config field, append "(copy)" to the display name, and append to the
    /// owning Type's schema. Member Page files are NOT touched (per locked
    /// rule: "add property = schema-only write" — new copies start empty
    /// on every member entity, ready to fill).
    func duplicateProperty(id propertyID: String, in typeID: String) async throws {
        try withPendingError {
            guard let i = types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            guard let j = types[i].properties.firstIndex(where: { $0.id == propertyID }) else {
                throw PageTypeManagerError.propertyNotFound
            }

            var duplicated = types[i].properties[j]
            duplicated.id = ReservedPropertyID.mintUserPropertyID()
            duplicated.name = "\(duplicated.name) (copy)"

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
        }
    }

    // MARK: - Update property (transform-based per-config edit)

    /// Apply an in-place transform to a PropertyDefinition's per-config
    /// fields. Validates against the rest of the schema, persists the
    /// parent PageType sidecar atomically, and upserts into the SQLite
    /// index. Used by the View Settings Edit Property pane to live-save
    /// option-list / displayAs / dateFormat / numberFormat / accept / icon
    /// changes without bespoke per-field manager methods.
    func updateProperty(
        id propertyID: String,
        in typeID: String,
        transform: (inout PropertyDefinition) -> Void
    ) async throws {
        try withPendingError {
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
        }
    }

    func deleteProperty(id propertyID: String, in typeID: String) async throws {
        try withPendingError {
            try PerTypeSchemaService.deleteProperty(id: propertyID, in: typeID, on: schemaAdapter)
        }
        // Scrub the now-dangling property id from every SavedView of this
        // container so a view grouped/sorted by it doesn't collapse into one
        // "No Value" bucket or silently un-sort. Disk-safe: routes through the
        // same fresh-from-disk read-modify-write as the other view mutations.
        try await mutateViews(in: typeID) { views in
            for i in views.indices {
                SavedViewMutations.scrubDeletedProperty(&views[i], propertyID: propertyID)
            }
        }
    }

    // MARK: - Reorder property

    /// Moves a property to a new index within the schema's `properties` array.
    /// Schema-only write — member files are not touched.
    func reorderProperty(id propertyID: String, in typeID: String, toIndex newIndex: Int) async throws {
        try withPendingError {
            try PerTypeSchemaService.reorderProperty(id: propertyID, in: typeID, toIndex: newIndex, on: schemaAdapter)
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
        try withPendingError {
            try PerTypeSchemaService.changeType(
                of: propertyID,
                in: typeID,
                to: newType,
                dropConflictingValues: dropConflictingValues,
                on: schemaAdapter)
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
                let data = try AtomicYAMLMarkdown.encode(
                    frontmatter: fm, body: body,
                    preservingFrom: pageURL, modeledKeys: PageFrontmatter.modeledKeys)
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
