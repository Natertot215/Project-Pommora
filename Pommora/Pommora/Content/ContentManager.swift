import Foundation
import Observation

/// Manages Pages (`.md`) + Items (`.json`) inside a Vault. The spec allows
/// Content to live either directly in a Vault's root folder or inside a
/// Collection sub-folder — both are first-class. Collection-scoped state and
/// vault-root-scoped state are kept in parallel dictionaries to avoid nullable
/// `Collection` plumbing through every CRUD signature.
///
/// PageMeta = lightweight tracking value (no body in memory); full PageFile is
/// loaded on demand by the editor (post-v0.2). Items load entirely since they're
/// small row-shaped records.
///
/// All CRUD methods take the parent `Vault` because Page/Item validation needs
/// the Vault's property schema. Validation runs before every write.
///
/// CRUD methods are split into `ContentManager+CRUD.swift` for legibility —
/// this file holds storage + accessors + load paths only.
@MainActor
@Observable
final class ContentManager {
    /// Collection-scoped Pages keyed by Collection.id.
    /// Note: relaxed from `private(set)` to internal-set so the
    /// `ContentManager+CRUD.swift` extension can mutate. Tests + UI still go
    /// through the accessor methods below; nothing outside the type reaches
    /// into the dictionaries by index.
    var pagesByCollection: [String: [PageMeta]] = [:]
    /// Collection-scoped Items keyed by Collection.id.
    var itemsByCollection: [String: [Item]] = [:]
    /// Vault-root Pages (directly inside the Vault folder, NOT in a Collection)
    /// keyed by Vault.id.
    var pagesByVaultRoot: [String: [PageMeta]] = [:]
    /// Vault-root Items keyed by Vault.id. Surfaces only in detail-pane Tables
    /// in v0.2 — sidebar doesn't render Items — but the data layer supports it.
    var itemsByVaultRoot: [String: [Item]] = [:]
    var pendingError: (any Error)?

    // nexus + contextProvider used by the +CRUD extension. Internal (not
    // private) so the extension can read them across the file boundary.
    let nexus: Nexus
    let contextProvider: @MainActor () -> NexusContext

    init(nexus: Nexus, contextProvider: @escaping @MainActor () -> NexusContext) {
        self.nexus = nexus
        self.contextProvider = contextProvider
    }

    // MARK: - Accessors

    func pages(in collection: Collection) -> [PageMeta] {
        pagesByCollection[collection.id] ?? []
    }

    func items(in collection: Collection) -> [Item] {
        itemsByCollection[collection.id] ?? []
    }

    func pages(in vault: Vault) -> [PageMeta] {
        pagesByVaultRoot[vault.id] ?? []
    }

    func items(in vault: Vault) -> [Item] {
        itemsByVaultRoot[vault.id] ?? []
    }

    // MARK: - Resolvers

    /// Find the Vault (and optionally Collection) that a `PageMeta` lives in.
    /// Returns `nil` if the Page isn't in any loaded Vault. Used by the editor
    /// (inspector + rename + saver construction) when only PageMeta is in hand.
    /// Brute-force O(N+M) walker; SQLite-backed lookup arrives with v0.4.0.
    func resolveParent(
        for page: PageMeta, vaultManager: VaultManager
    )
        -> (vault: Vault, collection: Pommora.Collection?)?
    {
        for vault in vaultManager.vaults {
            if pages(in: vault).contains(where: { $0.id == page.id }) {
                return (vault, nil)
            }
            for collection in vaultManager.collections(in: vault) {
                if pages(in: collection).contains(where: { $0.id == page.id }) {
                    return (vault, collection)
                }
            }
        }
        return nil
    }

    // MARK: - Path helpers (vault-root)

    /// Vault.folderURL isn't a stored property — it's always derived from the
    /// nexus root + the vault's title. Centralized here so every vault-root
    /// CRUD path uses the same derivation. Internal so the +CRUD extension
    /// can call it across the file boundary.
    func folderURL(for vault: Vault) -> URL {
        NexusPaths.vaultFolderURL(forTitle: vault.title, in: nexus)
    }

    // MARK: - Load (Collection-scoped)

    func loadAll(for collection: Collection) async {
        do {
            let pageFiles = try Filesystem.children(of: collection.folderURL) { url in
                url.pathExtension == "md"
            }
            let pageMetas: [PageMeta] = pageFiles.compactMap { url in
                guard let pf = try? PageFile.load(from: url) else { return nil }
                return PageMeta(id: pf.frontmatter.id, title: pf.title, url: url, frontmatter: pf.frontmatter)
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

            let itemFiles = try Filesystem.children(of: collection.folderURL) { url in
                url.pathExtension == "json"
            }
            let items: [Item] = itemFiles.compactMap { try? Item.load(from: $0) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

            pagesByCollection[collection.id] = pageMetas
            itemsByCollection[collection.id] = items
            pendingError = nil
        } catch {
            pagesByCollection[collection.id] = []
            itemsByCollection[collection.id] = []
            pendingError = error
        }
    }

    // MARK: - Load (vault-root)

    /// Scans the vault's root folder for `.md` Pages and `.json` Items DIRECTLY
    /// (non-recursive — does not descend into Collection sub-folders, since
    /// those are loaded separately via `loadAll(for: collection)`).
    /// Skips the `_vault.json` sidecar (any `_`-prefixed file) and `_collection.json`
    /// sidecars (also `_`-prefixed but only ever found in sub-folders).
    func loadAll(for vault: Vault) async {
        let folder = folderURL(for: vault)
        do {
            let pageFiles = try Filesystem.children(of: folder) { url in
                url.pathExtension == "md"
                    && !url.lastPathComponent.hasPrefix("_")
            }
            let pageMetas: [PageMeta] = pageFiles.compactMap { url in
                guard let pf = try? PageFile.load(from: url) else { return nil }
                return PageMeta(id: pf.frontmatter.id, title: pf.title, url: url, frontmatter: pf.frontmatter)
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

            let itemFiles = try Filesystem.children(of: folder) { url in
                url.pathExtension == "json"
                    && !url.lastPathComponent.hasPrefix("_")
            }
            let items: [Item] = itemFiles.compactMap { try? Item.load(from: $0) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

            pagesByVaultRoot[vault.id] = pageMetas
            itemsByVaultRoot[vault.id] = items
            pendingError = nil
        } catch {
            pagesByVaultRoot[vault.id] = []
            itemsByVaultRoot[vault.id] = []
            pendingError = error
        }
    }
}
