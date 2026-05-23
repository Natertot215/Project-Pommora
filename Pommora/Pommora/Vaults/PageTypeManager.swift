import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderPageTypes/Collections

@MainActor
@Observable
final class PageTypeManager {
    private(set) var types: [PageType] = []
    private(set) var collectionsByType: [String: [Collection]] = [:]
    var pendingError: (any Error)?

    private let nexus: Nexus

    /// Current Nexus ID — used by the drag system's cross-window guard.
    var nexusID: String { nexus.id }

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func collections(in pageType: PageType) -> [Collection] {
        collectionsByType[pageType.id] ?? []
    }

    // MARK: - Load

    func loadAll() async {
        do {
            // Top-level folders inside nexus root that contain a schema sidecar
            let topLevel = try Filesystem.childFolders(of: nexus.rootURL)
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .filter { !$0.lastPathComponent.hasPrefix("_") }
                .filter { $0.lastPathComponent != "Agenda" }
                .filter { $0.lastPathComponent != ".trash" }

            var loadedTypes: [PageType] = []
            var loadedCols: [String: [Collection]] = [:]

            for folder in topLevel {
                let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)
                guard Filesystem.fileExists(at: metaURL),
                    let pageType = try? PageType.load(from: metaURL)
                else { continue }
                loadedTypes.append(pageType)

                // Discover Collections (sub-folders with schema sidecar; skip _- and .-prefixed)
                let cols = try Filesystem.childFolders(of: folder)
                    .filter { !$0.lastPathComponent.hasPrefix("_") }
                    .filter { !$0.lastPathComponent.hasPrefix(".") }
                    .compactMap { folder -> Pommora.Collection? in
                        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)
                        guard Filesystem.fileExists(at: metaURL) else { return nil }
                        return try? Pommora.Collection.load(from: metaURL)
                    }
                loadedCols[pageType.id] = OrderResolver.resolve(
                    cols,
                    persistedOrder: pageType.collectionOrder,
                    titleKeyPath: \Pommora.Collection.title
                )
            }

            self.types = OrderResolver.resolve(
                loadedTypes,
                persistedOrder: readPersistedPageTypeOrder(),
                titleKeyPath: \PageType.title
            )
            self.collectionsByType = loadedCols
            self.pendingError = nil
        } catch {
            self.types = []
            self.collectionsByType = [:]
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
            collectionsByType[pageType.id] = []
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
                // Rebuild Collection in-memory under new parent path (id + vault_id unchanged;
                // schema sidecar moved with its folder, just re-derive folderURL).
                // Preserve pageOrder/itemOrder so a Page Type rename doesn't drop persisted ordering.
                if let oldCols = collectionsByType[pageType.id] {
                    let rebuilt = oldCols.map { c -> Pommora.Collection in
                        let newCollURL = newFolder.appendingPathComponent(c.title, isDirectory: true)
                        return Pommora.Collection(
                            id: c.id,
                            vaultID: c.vaultID,
                            title: c.title,
                            folderURL: newCollURL,
                            modifiedAt: c.modifiedAt,
                            pageOrder: c.pageOrder,
                            itemOrder: c.itemOrder
                        )
                    }
                    collectionsByType[pageType.id] = rebuilt
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
            collectionsByType.removeValue(forKey: pageType.id)
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Collection CRUD

    func createCollection(name: String, inPageType pageType: PageType) async throws {
        do {
            let existing = collectionsByType[pageType.id] ?? []
            try CollectionValidator.validate(title: name, existingInVault: existing)

            let folder = NexusPaths.collectionFolderURL(
                forTitle: name, inVaultTitled: pageType.title, in: nexus
            )
            let now = Date()
            let coll = Collection(
                id: ULID.generate(),
                vaultID: pageType.id,
                title: name,
                folderURL: folder,
                modifiedAt: now
            )
            let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)
            try Filesystem.createFolderWithMetadata(
                folderURL: folder, metadataURL: metaURL, metadata: coll
            )

            var arr = existing
            arr.append(coll)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: pageType.collectionOrder,
                titleKeyPath: \Pommora.Collection.title
            )
            collectionsByType[pageType.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renameCollection(_ collection: Pommora.Collection, to newName: String) async throws {
        do {
            guard let pageType = types.first(where: { $0.id == collection.vaultID }) else { return }
            let existing = collectionsByType[pageType.id] ?? []
            try CollectionValidator.validate(
                title: newName, existingInVault: existing, excluding: collection
            )

            let newURL = NexusPaths.collectionFolderURL(
                forTitle: newName, inVaultTitled: pageType.title, in: nexus
            )
            try Filesystem.renameFolder(from: collection.folderURL, to: newURL)

            // Bump modified_at in the sidecar at its new location. Preserve
            // pageOrder/itemOrder so a rename doesn't drop persisted ordering.
            let now = Date()
            let updated = Pommora.Collection(
                id: collection.id,
                vaultID: collection.vaultID,
                title: newName,
                folderURL: newURL,
                modifiedAt: now,
                pageOrder: collection.pageOrder,
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
                    persistedOrder: pageType.collectionOrder,
                    titleKeyPath: \Pommora.Collection.title
                )
            }
            collectionsByType[pageType.id] = arr
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func deleteCollection(_ collection: Pommora.Collection) async throws {
        do {
            try Filesystem.moveToTrash(collection.folderURL, in: nexus)
            var arr = collectionsByType[collection.vaultID] ?? []
            arr.removeAll { $0.id == collection.id }
            collectionsByType[collection.vaultID] = arr
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

    /// Reorders Collections within `pageType`. New ID order persists to the parent
    /// Page Type's schema sidecar.
    func reorderCollections(in pageType: PageType, fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = collectionsByType[pageType.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        collectionsByType[pageType.id] = arr
        do {
            try OrderPersister.setCollectionOrder(arr.map(\.id), in: pageType, nexus: nexus)
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
