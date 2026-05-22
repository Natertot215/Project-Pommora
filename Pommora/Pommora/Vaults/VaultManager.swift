import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderVaults/Collections

@MainActor
@Observable
final class VaultManager {
    private(set) var vaults: [Vault] = []
    private(set) var collectionsByVault: [String: [Collection]] = [:]
    var pendingError: (any Error)?

    private let nexus: Nexus

    /// Current Nexus ID — used by the drag system's cross-window guard.
    var nexusID: String { nexus.id }

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func collections(in vault: Vault) -> [Collection] {
        collectionsByVault[vault.id] ?? []
    }

    // MARK: - Load

    func loadAll() async {
        do {
            // Top-level folders inside nexus root that contain _vault.json
            let topLevel = try Filesystem.childFolders(of: nexus.rootURL)
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .filter { !$0.lastPathComponent.hasPrefix("_") }
                .filter { $0.lastPathComponent != "Agenda" }
                .filter { $0.lastPathComponent != ".trash" }

            var loadedVaults: [Vault] = []
            var loadedCols: [String: [Collection]] = [:]

            for folder in topLevel {
                let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)
                guard Filesystem.fileExists(at: metaURL),
                    let vault = try? Vault.load(from: metaURL)
                else { continue }
                loadedVaults.append(vault)

                // Discover Collections (sub-folders with schema sidecar; skip _- and .-prefixed)
                let cols = try Filesystem.childFolders(of: folder)
                    .filter { !$0.lastPathComponent.hasPrefix("_") }
                    .filter { !$0.lastPathComponent.hasPrefix(".") }
                    .compactMap { folder -> Pommora.Collection? in
                        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)
                        guard Filesystem.fileExists(at: metaURL) else { return nil }
                        return try? Pommora.Collection.load(from: metaURL)
                    }
                loadedCols[vault.id] = OrderResolver.resolve(
                    cols,
                    persistedOrder: vault.collectionOrder,
                    titleKeyPath: \Pommora.Collection.title
                )
            }

            self.vaults = OrderResolver.resolve(
                loadedVaults,
                persistedOrder: readPersistedVaultOrder(),
                titleKeyPath: \Vault.title
            )
            self.collectionsByVault = loadedCols
            self.pendingError = nil
        } catch {
            self.vaults = []
            self.collectionsByVault = [:]
            self.pendingError = error
        }
    }

    // MARK: - Vault CRUD

    func createVault(name: String, icon: String?) async throws {
        do {
            try VaultValidator.validate(title: name, existing: vaults)

            let vault = Vault(
                id: ULID.generate(),
                title: name,
                icon: icon,
                properties: [],
                views: [],
                modifiedAt: Date()
            )
            let folder = NexusPaths.vaultFolderURL(forTitle: name, in: nexus)
            let meta = NexusPaths.vaultMetadataURL(forTitle: name, in: nexus)
            try Filesystem.createFolderWithMetadata(folderURL: folder, metadataURL: meta, metadata: vault)

            vaults.append(vault)
            collectionsByVault[vault.id] = []
            vaults = OrderResolver.resolve(
                vaults,
                persistedOrder: readPersistedVaultOrder(),
                titleKeyPath: \Vault.title
            )
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renameVault(_ vault: Vault, to newName: String) async throws {
        do {
            try VaultValidator.validate(title: newName, existing: vaults, excluding: vault)

            let oldFolder = NexusPaths.vaultFolderURL(forTitle: vault.title, in: nexus)
            let newFolder = NexusPaths.vaultFolderURL(forTitle: newName, in: nexus)
            try Filesystem.renameFolder(from: oldFolder, to: newFolder)

            var updated = vault
            updated.title = newName
            updated.modifiedAt = Date()
            let newMeta = NexusPaths.vaultMetadataURL(forTitle: newName, in: nexus)
            do {
                try updated.save(to: newMeta)
            } catch let saveError {
                // Roll back folder rename. Per spec: do NOT touch
                // collectionsByVault here — in-memory rebuild only runs on the
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

            if let i = vaults.firstIndex(where: { $0.id == vault.id }) {
                vaults[i] = updated
                // Rebuild Collection in-memory under new parent path (id + vault_id unchanged;
                // _collection.json sidecar moved with its folder, just re-derive folderURL).
                // Preserve pageOrder/itemOrder so a vault rename doesn't drop persisted ordering.
                if let oldCols = collectionsByVault[vault.id] {
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
                    collectionsByVault[vault.id] = rebuilt
                }
                vaults = OrderResolver.resolve(
                    vaults,
                    persistedOrder: readPersistedVaultOrder(),
                    titleKeyPath: \Vault.title
                )
            }
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func updateVaultIcon(_ vault: Vault, to icon: String?) async throws {
        do {
            var updated = vault
            updated.icon = icon
            updated.modifiedAt = Date()
            let meta = NexusPaths.vaultMetadataURL(forTitle: vault.title, in: nexus)
            try updated.save(to: meta)
            if let i = vaults.firstIndex(where: { $0.id == vault.id }) {
                vaults[i] = updated
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func deleteVault(_ vault: Vault) async throws {
        do {
            let folder = NexusPaths.vaultFolderURL(forTitle: vault.title, in: nexus)
            try Filesystem.moveToTrash(folder, in: nexus)
            vaults.removeAll { $0.id == vault.id }
            collectionsByVault.removeValue(forKey: vault.id)
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Collection CRUD

    func createCollection(name: String, inVault vault: Vault) async throws {
        do {
            let existing = collectionsByVault[vault.id] ?? []
            try CollectionValidator.validate(title: name, existingInVault: existing)

            let folder = NexusPaths.collectionFolderURL(
                forTitle: name, inVaultTitled: vault.title, in: nexus
            )
            let now = Date()
            let coll = Collection(
                id: ULID.generate(),
                vaultID: vault.id,
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
                persistedOrder: vault.collectionOrder,
                titleKeyPath: \Pommora.Collection.title
            )
            collectionsByVault[vault.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renameCollection(_ collection: Pommora.Collection, to newName: String) async throws {
        do {
            guard let vault = vaults.first(where: { $0.id == collection.vaultID }) else { return }
            let existing = collectionsByVault[vault.id] ?? []
            try CollectionValidator.validate(
                title: newName, existingInVault: existing, excluding: collection
            )

            let newURL = NexusPaths.collectionFolderURL(
                forTitle: newName, inVaultTitled: vault.title, in: nexus
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
                    persistedOrder: vault.collectionOrder,
                    titleKeyPath: \Pommora.Collection.title
                )
            }
            collectionsByVault[vault.id] = arr
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
            var arr = collectionsByVault[collection.vaultID] ?? []
            arr.removeAll { $0.id == collection.id }
            collectionsByVault[collection.vaultID] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Reorders Vaults in response to a sidebar drag (v0.2.8.0). Matches the
    /// SwiftUI `.onMove(perform:)` signature. New full ID order persists to
    /// `.nexus/state.json`.
    func reorderVaults(fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = vaults
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != vaults else { return }
        vaults = arr
        do {
            try OrderPersister.setVaultOrder(arr.map(\.id), in: nexus)
        } catch {
            self.pendingError = error
        }
    }

    /// Reorders Collections within `vault`. New ID order persists to the parent
    /// Vault's `_vault.json` sidecar.
    func reorderCollections(in vault: Vault, fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = collectionsByVault[vault.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        collectionsByVault[vault.id] = arr
        do {
            try OrderPersister.setCollectionOrder(arr.map(\.id), in: vault, nexus: nexus)
            // Keep the in-memory Vault's collectionOrder in sync.
            if let i = vaults.firstIndex(where: { $0.id == vault.id }) {
                vaults[i].collectionOrder = arr.map(\.id)
            }
        } catch {
            self.pendingError = error
        }
    }

    /// Reads the persisted Vault sibling order from `.nexus/state.json`. Returns
    /// nil if no state.json exists or no `vaultOrder` has been recorded — the
    /// resolver falls back to alphabetic in that case.
    private func readPersistedVaultOrder() -> [String]? {
        let url = NexusPaths.nexusStateURL(in: nexus)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (try? AtomicJSON.decode(NexusState.self, from: url))?.vaultOrder
    }
}
