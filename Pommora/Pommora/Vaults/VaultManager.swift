import Foundation
import Observation

@MainActor
@Observable
final class VaultManager {
    private(set) var vaults: [Vault] = []
    private(set) var collectionsByVault: [String: [Collection]] = [:]
    var pendingError: (any Error)?

    private let nexus: Nexus

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
                let metaURL = folder.appendingPathComponent("_vault.json")
                guard Filesystem.fileExists(at: metaURL),
                      let vault = try? Vault.load(from: metaURL)
                else { continue }
                loadedVaults.append(vault)

                // Discover Collections (sub-folders with _collection.json sidecar; skip _- and .-prefixed)
                let cols = try Filesystem.childFolders(of: folder)
                    .filter { !$0.lastPathComponent.hasPrefix("_") }
                    .filter { !$0.lastPathComponent.hasPrefix(".") }
                    .compactMap { folder -> Collection? in
                        let metaURL = folder.appendingPathComponent("_collection.json")
                        guard Filesystem.fileExists(at: metaURL) else { return nil }
                        return try? Collection.load(from: metaURL)
                    }
                    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                loadedCols[vault.id] = cols
            }

            self.vaults = loadedVaults.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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
        vaults.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func renameVault(_ vault: Vault, to newName: String) async throws {
        try VaultValidator.validate(title: newName, existing: vaults, excluding: vault)

        let oldFolder = NexusPaths.vaultFolderURL(forTitle: vault.title, in: nexus)
        let newFolder = NexusPaths.vaultFolderURL(forTitle: newName, in: nexus)
        try Filesystem.renameFolder(from: oldFolder, to: newFolder)

        var updated = vault
        updated.title = newName
        updated.modifiedAt = Date()
        let newMeta = NexusPaths.vaultMetadataURL(forTitle: newName, in: nexus)
        try updated.save(to: newMeta)

        if let i = vaults.firstIndex(where: { $0.id == vault.id }) {
            vaults[i] = updated
            // Rebuild Collection in-memory under new parent path (id + vault_id unchanged;
            // _collection.json sidecar moved with its folder, just re-derive folderURL).
            if let oldCols = collectionsByVault[vault.id] {
                let rebuilt = oldCols.map { c -> Collection in
                    let newCollURL = newFolder.appendingPathComponent(c.title, isDirectory: true)
                    return Collection(
                        id: c.id,
                        vaultID: c.vaultID,
                        title: c.title,
                        folderURL: newCollURL,
                        modifiedAt: c.modifiedAt
                    )
                }
                collectionsByVault[vault.id] = rebuilt
            }
            vaults.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    func updateVaultIcon(_ vault: Vault, to icon: String?) async throws {
        var updated = vault
        updated.icon = icon
        updated.modifiedAt = Date()
        let meta = NexusPaths.vaultMetadataURL(forTitle: vault.title, in: nexus)
        try updated.save(to: meta)
        if let i = vaults.firstIndex(where: { $0.id == vault.id }) {
            vaults[i] = updated
        }
    }

    func deleteVault(_ vault: Vault) async throws {
        let folder = NexusPaths.vaultFolderURL(forTitle: vault.title, in: nexus)
        try Filesystem.deleteFolder(at: folder)
        vaults.removeAll { $0.id == vault.id }
        collectionsByVault.removeValue(forKey: vault.id)
    }

    // MARK: - Collection CRUD

    func createCollection(name: String, inVault vault: Vault) async throws {
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
        let metaURL = folder.appendingPathComponent("_collection.json")
        try Filesystem.createFolderWithMetadata(
            folderURL: folder, metadataURL: metaURL, metadata: coll
        )

        var arr = existing
        arr.append(coll)
        arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        collectionsByVault[vault.id] = arr
    }

    func renameCollection(_ collection: Collection, to newName: String) async throws {
        guard let vault = vaults.first(where: { $0.id == collection.vaultID }) else { return }
        let existing = collectionsByVault[vault.id] ?? []
        try CollectionValidator.validate(
            title: newName, existingInVault: existing, excluding: collection
        )

        let newURL = NexusPaths.collectionFolderURL(
            forTitle: newName, inVaultTitled: vault.title, in: nexus
        )
        try Filesystem.renameFolder(from: collection.folderURL, to: newURL)

        // Bump modified_at in the sidecar at its new location
        let now = Date()
        let updated = Collection(
            id: collection.id,
            vaultID: collection.vaultID,
            title: newName,
            folderURL: newURL,
            modifiedAt: now
        )
        let metaURL = newURL.appendingPathComponent("_collection.json")
        try updated.save(to: metaURL)

        var arr = existing
        if let i = arr.firstIndex(where: { $0.id == collection.id }) {
            arr[i] = updated
            arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        collectionsByVault[vault.id] = arr
    }

    func deleteCollection(_ collection: Collection) async throws {
        try Filesystem.deleteFolder(at: collection.folderURL)
        var arr = collectionsByVault[collection.vaultID] ?? []
        arr.removeAll { $0.id == collection.id }
        collectionsByVault[collection.vaultID] = arr
    }
}
