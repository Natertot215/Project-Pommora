import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderPageTypes/Collections

@MainActor
@Observable
final class PageTypeManager {
    private(set) var types: [PageType] = []
    private(set) var pageCollectionsByType: [String: [PageCollection]] = [:]
    /// Third tier on the Pages side (F.1.g). Folders indexed by their parent
    /// PageCollection.id (NOT by PageType.id — Folders are Collection-local).
    /// A Collection without any Folders maps to an empty array; lookup-by-id
    /// returns `[]` for unknown collection IDs.
    private(set) var foldersByCollection: [String: [Folder]] = [:]
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

    func pageCollections(in pageType: PageType) -> [PageCollection] {
        pageCollectionsByType[pageType.id] ?? []
    }

    /// Returns the Folders inside `collection`, sorted by the persisted
    /// `folderOrder` on the Collection (with an alphabetic tail for unranked
    /// entries via `OrderResolver`).
    func folders(in collection: PageCollection) -> [Folder] {
        foldersByCollection[collection.id] ?? []
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
            var loadedFolders: [String: [Folder]] = [:]

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

                        // F.1.g — walk this Collection's sub-folders for
                        // `_folder.json` sidecars. A sub-folder without one is
                        // either still tagged-up by F.1.i's auto-tag pass
                        // (next launch) or an intentional Obsidian-style
                        // adopted folder; either way we skip it here.
                        let collectionFolders = (try? Filesystem.childFolders(of: sub)
                            .filter { !$0.lastPathComponent.hasPrefix("_") }
                            .filter { !$0.lastPathComponent.hasPrefix(".") }
                            .compactMap { folderSub -> Folder? in
                                let folderMetaURL = folderSub.appendingPathComponent(
                                    NexusPaths.folderSidecarFilename
                                )
                                guard Filesystem.fileExists(at: folderMetaURL),
                                    var f = try? Folder.load(from: folderMetaURL)
                                else { return nil }
                                if f.views.isEmpty {
                                    f.views = [
                                        SavedView.defaultTable(
                                            visiblePropertyIDs: parentPropertyIDs
                                        )
                                    ]
                                    try? f.save(to: folderMetaURL)
                                }
                                return f
                            }) ?? []
                        loadedFolders[collection.id] = OrderResolver.resolve(
                            collectionFolders,
                            persistedOrder: collection.folderOrder,
                            titleKeyPath: \Folder.title
                        )

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
            self.foldersByCollection = loadedFolders
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
            //
            // Folders ride this same defensive sync (F.1.g) — parent
            // PageCollection rows MUST be upserted before Folder rows so the
            // application-layer FK invariant holds even if upstream code
            // races a query before populate runs.
            if let updater = indexUpdater {
                for pageType in self.types {
                    try? updater.upsertPageType(pageType)
                    for collection in self.pageCollectionsByType[pageType.id] ?? [] {
                        try? updater.upsertPageCollection(collection)
                        for folder in self.foldersByCollection[collection.id] ?? [] {
                            try? updater.upsertFolder(folder)
                        }
                    }
                }
            }
        } catch {
            self.types = []
            self.pageCollectionsByType = [:]
            self.foldersByCollection = [:]
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
                        // F.1.g — re-derive Folder folderURLs that nest under
                        // this Collection, so subsequent CRUD has a valid
                        // on-disk path. IDs unchanged; only the URL needs
                        // recomputing.
                        if let oldFolders = foldersByCollection[c.id] {
                            let rebuiltFolders = oldFolders.map { f -> Folder in
                                let newFolderURL = newCollURL.appendingPathComponent(
                                    f.title, isDirectory: true
                                )
                                return Folder(
                                    id: f.id,
                                    typeID: f.typeID,
                                    collectionID: f.collectionID,
                                    title: f.title,
                                    folderURL: newFolderURL,
                                    icon: f.icon,
                                    modifiedAt: f.modifiedAt,
                                    schemaVersion: f.schemaVersion,
                                    pageOrder: f.pageOrder,
                                    views: f.views
                                )
                            }
                            foldersByCollection[c.id] = rebuiltFolders
                        }
                        return PageCollection(
                            id: c.id,
                            typeID: c.typeID,
                            title: c.title,
                            folderURL: newCollURL,
                            modifiedAt: c.modifiedAt,
                            pageOrder: c.pageOrder,
                            folderOrder: c.folderOrder
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
            // pageOrder + folderOrder so a rename doesn't drop persisted ordering.
            let now = Date()
            let updated = PageCollection(
                id: collection.id,
                typeID: collection.typeID,
                title: newName,
                folderURL: newURL,
                modifiedAt: now,
                pageOrder: collection.pageOrder,
                folderOrder: collection.folderOrder
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

            // F.1.g — rebuild Folder folderURLs nested under this Collection
            // after its parent folder moved. IDs unchanged; only the URL
            // path needs recomputing.
            if let oldFolders = foldersByCollection[collection.id] {
                let rebuiltFolders = oldFolders.map { f -> Folder in
                    let newFolderURL = newURL.appendingPathComponent(
                        f.title, isDirectory: true
                    )
                    return Folder(
                        id: f.id,
                        typeID: f.typeID,
                        collectionID: f.collectionID,
                        title: f.title,
                        folderURL: newFolderURL,
                        icon: f.icon,
                        modifiedAt: f.modifiedAt,
                        schemaVersion: f.schemaVersion,
                        pageOrder: f.pageOrder,
                        views: f.views
                    )
                }
                foldersByCollection[collection.id] = rebuiltFolders
            }
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

            // F.1.g — the SQLite folders table cascades via ON DELETE CASCADE
            // FK on `page_collections(id)`, but the in-memory dictionary must
            // be cleared explicitly. Folders inside the deleted Collection
            // are gone from disk (parent folder moved to trash); pages inside
            // those Folders are also trashed.
            foldersByCollection.removeValue(forKey: collection.id)
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Folder CRUD (F.1.g)

    /// Creates a new Folder inside `collection`. Writes the on-disk
    /// `<nexus>/<type>/<collection>/<title>/_folder.json` sidecar,
    /// upserts the index row, and appends to `foldersByCollection`. Mints
    /// a default Table view via `SavedView.defaultTable(visiblePropertyIDs:)`
    /// keyed off the grandparent PageType's property schema. Locked decision:
    /// fresh Folders start cold — they do NOT copy the parent Collection's
    /// `views[0]` config (Collection independence rule extends to Folders).
    @discardableResult
    func createFolder(
        in collection: PageCollection,
        title: String,
        icon: String? = nil
    ) async throws -> Folder {
        do {
            guard let pageType = types.first(where: { $0.id == collection.typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            let existing = foldersByCollection[collection.id] ?? []
            try FolderValidator.validate(title: title, existingInCollection: existing)

            let folderURL = NexusPaths.folderFolderURL(
                in: nexus.rootURL,
                typeFolderName: pageType.title,
                collectionFolderName: collection.title,
                folderFolderName: title
            )
            let metaURL = folderURL.appendingPathComponent(NexusPaths.folderSidecarFilename)
            let now = Date()
            let folder = Folder(
                id: ULID.generate(),
                typeID: pageType.id,
                collectionID: collection.id,
                title: title,
                folderURL: folderURL,
                icon: icon,
                modifiedAt: now,
                views: [
                    SavedView.defaultTable(
                        visiblePropertyIDs: pageType.properties.map(\.id)
                    )
                ]
            )
            try Filesystem.createFolderWithMetadata(
                folderURL: folderURL, metadataURL: metaURL, metadata: folder
            )

            if let updater = indexUpdater {
                do { try updater.upsertFolder(folder) } catch { self.pendingError = error }
            }

            var arr = existing
            arr.append(folder)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: collection.folderOrder,
                titleKeyPath: \Folder.title
            )
            foldersByCollection[collection.id] = arr
            return folder
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Renames a Folder. Atomic disk rename → sidecar rewrite at new path
    /// with bumped modifiedAt → in-memory update. Preserves `pageOrder` /
    /// `views` / `icon` across the rename. On save failure rolls back the
    /// folder rename and throws (combined `RenameAtomicityError` if the
    /// rollback itself fails).
    func renameFolder(_ folder: Folder, to newName: String) async throws {
        do {
            guard let pageType = types.first(where: { $0.id == folder.typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            guard let collection = (pageCollectionsByType[folder.typeID] ?? [])
                .first(where: { $0.id == folder.collectionID })
            else {
                throw PageTypeManagerError.typeNotFound
            }
            let existing = foldersByCollection[collection.id] ?? []
            try FolderValidator.validate(
                title: newName, existingInCollection: existing, excluding: folder
            )

            let newURL = NexusPaths.folderFolderURL(
                in: nexus.rootURL,
                typeFolderName: pageType.title,
                collectionFolderName: collection.title,
                folderFolderName: newName
            )
            try Filesystem.renameFolder(from: folder.folderURL, to: newURL)

            let now = Date()
            let updated = Folder(
                id: folder.id,
                typeID: folder.typeID,
                collectionID: folder.collectionID,
                title: newName,
                folderURL: newURL,
                icon: folder.icon,
                modifiedAt: now,
                schemaVersion: folder.schemaVersion,
                pageOrder: folder.pageOrder,
                views: folder.views
            )
            let metaURL = newURL.appendingPathComponent(NexusPaths.folderSidecarFilename)
            do {
                try updated.save(to: metaURL)
            } catch let saveError {
                do {
                    try Filesystem.renameFolder(from: newURL, to: folder.folderURL)
                    throw saveError
                } catch let revertError {
                    let combined = RenameAtomicityError(
                        saveError: saveError, revertError: revertError
                    )
                    self.pendingError = combined
                    throw combined
                }
            }

            if let updater = indexUpdater {
                do { try updater.upsertFolder(updated) } catch { self.pendingError = error }
            }

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == folder.id }) {
                arr[i] = updated
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: collection.folderOrder,
                    titleKeyPath: \Folder.title
                )
            }
            foldersByCollection[collection.id] = arr
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    /// Updates a Folder's icon. Schema-only write at the sidecar; bumps
    /// `modifiedAt`. Pages-in-folders unaffected.
    func updateFolderIcon(_ folder: Folder, to icon: String?) async throws {
        do {
            var updated = folder
            updated.icon = icon
            updated.modifiedAt = Date()
            let metaURL = folder.folderURL.appendingPathComponent(
                NexusPaths.folderSidecarFilename
            )
            try updated.save(to: metaURL)
            if let updater = indexUpdater {
                do { try updater.upsertFolder(updated) } catch { self.pendingError = error }
            }
            var arr = foldersByCollection[folder.collectionID] ?? []
            if let i = arr.firstIndex(where: { $0.id == folder.id }) {
                arr[i] = updated
            }
            foldersByCollection[folder.collectionID] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Moves a Folder + every Page inside it to the nexus trash. The SQLite
    /// `folders` row deletion is explicit (no FK cascade across the
    /// `addPageFolderIDColumnIfMissing`-added pages.page_folder_id column
    /// since SQLite ALTER can't add the REFERENCES clause). Pages-in-folders
    /// remain indexed; the next IndexBuilder run reconciles their orphan
    /// `page_folder_id`.
    func deleteFolder(_ folder: Folder) async throws {
        do {
            try Filesystem.moveToTrash(folder.folderURL, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deleteFolder(id: folder.id) } catch { self.pendingError = error }
            }
            var arr = foldersByCollection[folder.collectionID] ?? []
            arr.removeAll { $0.id == folder.id }
            foldersByCollection[folder.collectionID] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Reorders Folders inside `collection` (intra-group only — Folders never
    /// interleave with root Pages). Persists the new order to the parent
    /// Collection's `_pagecollection.json` `folder_order` field via
    /// `OrderPersister.setFolderOrder`. Also bumps the in-memory
    /// PageCollection's `folderOrder` so subsequent loadAll's OrderResolver
    /// reads the persisted value back consistently.
    func reorderFolders(
        in collection: PageCollection,
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        var arr = foldersByCollection[collection.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        foldersByCollection[collection.id] = arr
        do {
            try OrderPersister.setFolderOrder(arr.map(\.id), in: collection)
            // Keep the in-memory PageCollection's folderOrder in sync.
            if let typeArr = pageCollectionsByType[collection.typeID],
                let ci = typeArr.firstIndex(where: { $0.id == collection.id })
            {
                var c = typeArr[ci]
                c.folderOrder = arr.map(\.id)
                pageCollectionsByType[collection.typeID]?[ci] = c
            }
        } catch {
            self.pendingError = error
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
    /// Type sidecars atomically. `definition.dualProperty.syncedPropertyDefinedOnTypeID`
    /// identifies the target type (PageType only in this manager — cross-side pairing goes
    /// via ItemTypeManager). `definition.dualProperty.syncedPropertyID` is used as the
    /// reverse property display name (caller convention at add-time; replaced by the minted
    /// ID after creation).
    func addProperty(_ definition: PropertyDefinition, to typeID: String) async throws {
        do {
            guard let i = types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }

            var def = definition
            if def.id.isEmpty {
                def.id = ReservedPropertyID.mintUserPropertyID()
            }

            // Paired relation: route through DualRelationCoordinator.
            if def.type == .relation, let dualConfig = def.dualProperty {
                let targetTypeID = dualConfig.syncedPropertyDefinedOnTypeID
                guard let scope = def.relationScope else {
                    throw PageTypeManagerError.propertyNotFound
                }
                // Locate the target PageType in-memory (same manager, same nexus).
                guard let targetType = types.first(where: { $0.id == targetTypeID }) else {
                    throw PageTypeManagerError.typeNotFound
                }
                let sourceKind = DualRelationCoordinator.TypeKind.pageType(types[i])
                let targetKind = DualRelationCoordinator.TypeKind.pageType(targetType)
                // Reverse scope points back to source Type.
                let targetScope = PropertyDefinition.RelationScope.pageType(types[i].id)
                // Reverse name: caller puts desired reverse name in syncedPropertyID at add-time.
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
                // Reload source type from disk so in-memory reflects the coordinator's write.
                let meta = NexusPaths.vaultMetadataURL(forTitle: types[i].title, in: nexus)
                if let reloaded = try? PageType.load(from: meta) {
                    types[i] = reloaded
                }
                // Also reload target type if it's a different type.
                if targetTypeID != typeID, let j = types.firstIndex(where: { $0.id == targetTypeID }) {
                    let targetMeta = NexusPaths.vaultMetadataURL(forTitle: targetType.title, in: nexus)
                    if let reloaded = try? PageType.load(from: targetMeta) {
                        types[j] = reloaded
                    }
                }
                if let updater = indexUpdater {
                    if let addedDef = types[i].properties.first(where: { $0.id == srcID }) {
                        let position = types[i].properties.count - 1
                        do {
                            try updater.upsertPropertyDefinition(
                                addedDef, owningTypeID: typeID, owningTypeKind: "page_type",
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

            let meta = NexusPaths.vaultMetadataURL(forTitle: updated.title, in: nexus)
            try updated.save(to: meta)

            if let updater = indexUpdater {
                let position = updated.properties.count - 1
                do { try updater.upsertPropertyDefinition(def, owningTypeID: typeID, owningTypeKind: "page_type", position: position) } catch { self.pendingError = error }
            }

            types[i] = updated
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
                throw PageTypeManagerError.typeNotFound
            }
            guard let propIndex = types[typeIndex].properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw PageTypeManagerError.propertyNotFound
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

            let meta = NexusPaths.vaultMetadataURL(forTitle: updated.title, in: nexus)
            try updated.save(to: meta)

            if let updater = indexUpdater {
                do { try updater.upsertPropertyDefinition(renamedDef, owningTypeID: typeID, owningTypeKind: "page_type", position: propIndex) } catch { self.pendingError = error }
            }

            types[typeIndex] = updated
        } catch {
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

            try PropertyDefinitionValidator.validate(duplicated, in: types[i].properties)

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
            try PropertyDefinitionValidator.validate(updatedDef, in: siblings)

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
        do {
            guard let typeIndex = types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            guard let propIndex = types[typeIndex].properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw PageTypeManagerError.propertyNotFound
            }

            let prop = types[typeIndex].properties[propIndex]

            // Paired relation: route through DualRelationCoordinator (cascades both sides).
            if prop.type == .relation, let dualConfig = prop.dualProperty {
                let targetTypeID = dualConfig.syncedPropertyDefinedOnTypeID
                let ownerKind = DualRelationCoordinator.TypeKind.pageType(types[typeIndex])
                // Locate reverse Type (PageType-to-PageType).
                if let targetType = types.first(where: { $0.id == targetTypeID }) {
                    let reverseKind = DualRelationCoordinator.TypeKind.pageType(targetType)
                    try DualRelationCoordinator.deletePair(
                        propertyID: propertyID,
                        owner: ownerKind,
                        reverse: reverseKind,
                        nexus: nexus
                    )
                    // Reload both types in-memory.
                    let meta = NexusPaths.vaultMetadataURL(forTitle: types[typeIndex].title, in: nexus)
                    if let reloaded = try? PageType.load(from: meta) {
                        types[typeIndex] = reloaded
                    }
                    if let j = types.firstIndex(where: { $0.id == targetTypeID }) {
                        let tMeta = NexusPaths.vaultMetadataURL(forTitle: targetType.title, in: nexus)
                        if let reloaded = try? PageType.load(from: tMeta) {
                            types[j] = reloaded
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
            let meta = NexusPaths.vaultMetadataURL(forTitle: updated.title, in: nexus)
            try tx.stage(updated, to: meta)

            // Stage member-file rewrites: strip the property key from every Page's frontmatter.
            let typeFolder = NexusPaths.vaultFolderURL(forTitle: updated.title, in: nexus)
            let pageFiles = try Filesystem.descendantFiles(
                of: typeFolder,
                where: { url in
                    url.pathExtension == "md"
                })
            for pageURL in pageFiles {
                var (fm, body) = try AtomicYAMLMarkdown.load(PageFrontmatter.self, from: pageURL)
                guard fm.properties[propertyID] != nil else { continue }
                fm.properties.removeValue(forKey: propertyID)
                let data = try AtomicYAMLMarkdown.encode(frontmatter: fm, body: body)
                tx.stage(payload: data, to: pageURL)
            }

            try tx.commit()

            if let updater = indexUpdater {
                do { try updater.deletePropertyDefinition(id: propertyID) } catch { self.pendingError = error }
            }

            types[typeIndex] = updated
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
                throw PageTypeManagerError.typeNotFound
            }
            guard let propIndex = types[typeIndex].properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw PageTypeManagerError.propertyNotFound
            }

            var props = types[typeIndex].properties
            let clampedIndex = min(max(newIndex, 0), props.count - 1)
            guard clampedIndex != propIndex else { return }

            guard clampedIndex >= 0 && clampedIndex < props.count else {
                throw PageTypeManagerError.indexOutOfBounds
            }

            props.move(
                fromOffsets: IndexSet(integer: propIndex),
                toOffset: clampedIndex > propIndex ? clampedIndex + 1 : clampedIndex)

            var updated = types[typeIndex]
            updated.properties = props
            updated.modifiedAt = Date()

            let meta = NexusPaths.vaultMetadataURL(forTitle: updated.title, in: nexus)
            try updated.save(to: meta)

            if let updater = indexUpdater {
                for (pos, def) in updated.properties.enumerated() {
                    do { try updater.upsertPropertyDefinition(def, owningTypeID: typeID, owningTypeKind: "page_type", position: pos) } catch { self.pendingError = error }
                }
            }

            types[typeIndex] = updated
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
            guard let typeIndex = types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            guard let propIndex = types[typeIndex].properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw PageTypeManagerError.propertyNotFound
            }

            let oldType = types[typeIndex].properties[propIndex].type

            if oldType == newType {
                // Lossless: schema-only write to bump modifiedAt.
                var updated = types[typeIndex]
                updated.properties[propIndex].type = newType
                updated.modifiedAt = Date()
                let meta = NexusPaths.vaultMetadataURL(forTitle: updated.title, in: nexus)
                try updated.save(to: meta)
                if let updater = indexUpdater {
                    let def = updated.properties[propIndex]
                    do { try updater.upsertPropertyDefinition(def, owningTypeID: typeID, owningTypeKind: "page_type", position: propIndex) } catch { self.pendingError = error }
                }
                types[typeIndex] = updated
                return
            }

            // Lossy cross-type change.
            guard dropConflictingValues else {
                throw PageTypeManagerError.lossyChangeRequiresConfirmation
            }

            var updated = types[typeIndex]
            updated.properties[propIndex].type = newType
            updated.modifiedAt = Date()

            let tx = SchemaTransaction()

            // Stage updated schema sidecar.
            let meta = NexusPaths.vaultMetadataURL(forTitle: updated.title, in: nexus)
            try tx.stage(updated, to: meta)

            // Stage member-file rewrites: strip the conflicting property value from
            // every Page's frontmatter so no stale cross-type value lingers.
            let typeFolder = NexusPaths.vaultFolderURL(forTitle: updated.title, in: nexus)
            let pageFiles = try Filesystem.descendantFiles(
                of: typeFolder,
                where: { url in
                    url.pathExtension == "md"
                })
            for pageURL in pageFiles {
                var (fm, body) = try AtomicYAMLMarkdown.load(PageFrontmatter.self, from: pageURL)
                guard fm.properties[propertyID] != nil else { continue }
                fm.properties.removeValue(forKey: propertyID)
                let data = try AtomicYAMLMarkdown.encode(frontmatter: fm, body: body)
                tx.stage(payload: data, to: pageURL)
            }

            try tx.commit()

            if let updater = indexUpdater {
                let def = updated.properties[propIndex]
                do { try updater.upsertPropertyDefinition(def, owningTypeID: typeID, owningTypeKind: "page_type", position: propIndex) } catch { self.pendingError = error }
            }

            types[typeIndex] = updated
        } catch {
            self.pendingError = error
            throw error
        }
    }
}
