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

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func pageCollections(in pageType: PageType) -> [PageCollection] {
        pageCollectionsByType[pageType.id] ?? []
    }

    // MARK: - Load

    func loadAll() async {
        do {
            // flatlayout: PageType folders sit at the Nexus root. Discovery
            // filters folders by presence of `_pagetype.json`; folders carrying
            // any of the other per-kind sidecars (Items/Agenda/Collection) or
            // no recognized sidecar are skipped. NexusAdopter handles surfacing
            // unrecognized folders for adoption (Phase 4).
            let root = nexus.rootURL

            // Legacy sidecar auto-heal — bridges pre-flatlayout nexuses whose
            // PageType folders still carry `_vault.json` / `_schema.json` (and
            // sub-folders carrying `_collection.json` / `_schema.json`).
            // Idempotent; no-op on already-migrated nexuses. NexusAdopter owns
            // the canonical migration path in Phase 4; this in-loader heal
            // remains as a belt-and-braces seam until Task 3.1 retires it.
            migrateLegacySidecarsIfNeeded(in: root)

            let topLevel = try Filesystem.childFolders(of: root)
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .filter { !$0.lastPathComponent.hasPrefix("_") }

            var loadedTypes: [PageType] = []
            var loadedCols: [String: [PageCollection]] = [:]

            for folder in topLevel {
                let metaURL = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
                guard Filesystem.fileExists(at: metaURL),
                    let pageType = try? PageType.load(from: metaURL)
                else { continue }
                loadedTypes.append(pageType)

                // Discover PageCollections (sub-folders with `_pagecollection.json`; skip _- and .-prefixed)
                let cols = try Filesystem.childFolders(of: folder)
                    .filter { !$0.lastPathComponent.hasPrefix("_") }
                    .filter { !$0.lastPathComponent.hasPrefix(".") }
                    .compactMap { folder -> PageCollection? in
                        let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
                        guard Filesystem.fileExists(at: metaURL) else { return nil }
                        return try? PageCollection.load(from: metaURL)
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
        } catch {
            self.types = []
            self.pageCollectionsByType = [:]
            self.pendingError = error
        }
    }

    // MARK: - PageType CRUD

    func createPageType(name: String, icon: String?) async throws {
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

            types.append(pageType)
            pageCollectionsByType[pageType.id] = []
            types = OrderResolver.resolve(
                types,
                persistedOrder: readPersistedPageTypeOrder(),
                titleKeyPath: \PageType.title
            )
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
            types.removeAll { $0.id == pageType.id }
            pageCollectionsByType.removeValue(forKey: pageType.id)
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - PageCollection CRUD

    func createPageCollection(name: String, inPageType pageType: PageType) async throws {
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

            var arr = existing
            arr.append(coll)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: pageType.collectionOrder,
                titleKeyPath: \PageCollection.title
            )
            pageCollectionsByType[pageType.id] = arr
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

    /// Belt-and-braces in-loader legacy sidecar rename. NexusAdopter is the
    /// canonical migration path (Phase 4); this in-loader heal stays in place
    /// until Task 3.1 retires the loader-side migration entirely.
    ///
    /// Walks the nexus root and, for any folder carrying a legacy sidecar
    /// (`_vault.json` or pre-flatlayout `_schema.json`), renames in place to
    /// `_pagetype.json`. Same treatment for nested Collection sub-folders:
    /// `_collection.json` / `_schema.json` → `_pagecollection.json`.
    /// Idempotent — no-op when the new filename already exists. Errors
    /// swallowed (best-effort).
    private func migrateLegacySidecarsIfNeeded(in root: URL) {
        let typeName = NexusPaths.pageTypeSidecarFilename
        let collectionName = NexusPaths.pageCollectionSidecarFilename
        let fm = FileManager.default
        guard let topLevel = try? Filesystem.childFolders(of: root) else { return }
        for folder in topLevel {
            let name = folder.lastPathComponent
            if name.hasPrefix(".") || name.hasPrefix("_") { continue }
            renameLegacySidecar(at: folder, legacyName: "_vault.json", newName: typeName, fm: fm)
            renameLegacySidecar(at: folder, legacyName: NexusPaths.schemaSidecarFilename, newName: typeName, fm: fm)
            guard let subs = try? Filesystem.childFolders(of: folder) else { continue }
            for sub in subs {
                let subName = sub.lastPathComponent
                if subName.hasPrefix(".") || subName.hasPrefix("_") { continue }
                renameLegacySidecar(at: sub, legacyName: "_collection.json", newName: collectionName, fm: fm)
                renameLegacySidecar(at: sub, legacyName: NexusPaths.schemaSidecarFilename, newName: collectionName, fm: fm)
            }
        }
    }

    private func renameLegacySidecar(at folder: URL, legacyName: String, newName: String, fm: FileManager) {
        let legacy = folder.appendingPathComponent(legacyName, isDirectory: false)
        let target = folder.appendingPathComponent(newName, isDirectory: false)
        guard fm.fileExists(atPath: legacy.path),
              !fm.fileExists(atPath: target.path)
        else { return }
        try? fm.moveItem(at: legacy, to: target)
    }
}
