import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderPages

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

    /// Current Nexus ID — used by the drag system's cross-window guard.
    var nexusID: String { nexus.id }

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

    /// Loads every `.md` Page and `.json` Item inside `collection.folderURL`,
    /// descending recursively through sub-folders. Sub-folders deeper than
    /// the locked 2-level Vault/Collection model aren't themselves Collections
    /// — their files roll up into this Collection (Obsidian-parity for
    /// adopted folder structures).
    ///
    /// Pages use the lenient loader so adopted `.md` files without Pommora
    /// frontmatter still surface; missing `id` is synthesized deterministically
    /// from the file's path relative to the Nexus root (stable across launches,
    /// not written back until the user edits).
    func loadAll(for collection: Pommora.Collection) async {
        let nexusRoot = nexus.rootURL
        do {
            let pageFiles = try Filesystem.descendantFiles(of: collection.folderURL) { url in
                url.pathExtension == "md" && !url.lastPathComponent.hasPrefix("_")
            }
            let unsortedPages: [PageMeta] = pageFiles.compactMap { url in
                guard let pf = try? PageFile.loadLenient(from: url, nexusRoot: nexusRoot)
                else { return nil }
                return PageMeta(
                    id: pf.frontmatter.id,
                    title: pf.title,
                    url: url,
                    frontmatter: pf.frontmatter
                )
            }
            let pageMetas = OrderResolver.resolve(
                unsortedPages,
                persistedOrder: collection.pageOrder,
                titleKeyPath: \PageMeta.title
            )

            let itemFiles = try Filesystem.descendantFiles(of: collection.folderURL) { url in
                url.pathExtension == "json" && !url.lastPathComponent.hasPrefix("_")
            }
            let unsortedItems: [Item] = itemFiles.compactMap { try? Item.load(from: $0) }
            let items = OrderResolver.resolve(
                unsortedItems,
                persistedOrder: collection.itemOrder,
                titleKeyPath: \Item.title
            )

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

    /// Scans the Vault root for `.md` Pages and `.json` Items, recursing into
    /// every sub-folder EXCEPT those that are themselves Collections — those
    /// roll up under `loadAll(for: collection)` instead. Deep sub-folders that
    /// aren't Collections (depth ≥ 2) contribute their files to the Vault root,
    /// matching Obsidian's "show every `.md` in the vault" semantics.
    ///
    /// Pages use the lenient loader so adopted Markdown surfaces even when
    /// it predates Pommora frontmatter.
    func loadAll(for vault: Vault) async {
        let folder = folderURL(for: vault)
        let nexusRoot = nexus.rootURL
        // Discover Collection sub-folders by sidecar presence so we exclude
        // their subtrees from the Vault-root walk — their files load via
        // `loadAll(for: collection)`, not here. Avoids needing a VaultManager
        // handle inside ContentManager.
        let allSubs = (try? Filesystem.childFolders(of: folder)) ?? []
        let collectionFolders = allSubs.filter { sub in
            Filesystem.fileExists(at: sub.appendingPathComponent(NexusPaths.schemaSidecarFilename))
        }
        let excludedCollectionFolders = Set(collectionFolders.map { $0.standardizedFileURL })
        do {
            let pageFiles = try Filesystem.descendantFiles(
                of: folder,
                excluding: excludedCollectionFolders
            ) { url in
                url.pathExtension == "md" && !url.lastPathComponent.hasPrefix("_")
            }
            let unsortedPages: [PageMeta] = pageFiles.compactMap { url in
                guard let pf = try? PageFile.loadLenient(from: url, nexusRoot: nexusRoot)
                else { return nil }
                return PageMeta(
                    id: pf.frontmatter.id,
                    title: pf.title,
                    url: url,
                    frontmatter: pf.frontmatter
                )
            }
            let pageMetas = OrderResolver.resolve(
                unsortedPages,
                persistedOrder: vault.pageOrder,
                titleKeyPath: \PageMeta.title
            )

            let itemFiles = try Filesystem.descendantFiles(
                of: folder,
                excluding: excludedCollectionFolders
            ) { url in
                url.pathExtension == "json" && !url.lastPathComponent.hasPrefix("_")
            }
            let unsortedItems: [Item] = itemFiles.compactMap { try? Item.load(from: $0) }
            let items = OrderResolver.resolve(
                unsortedItems,
                persistedOrder: vault.itemOrder,
                titleKeyPath: \Item.title
            )

            pagesByVaultRoot[vault.id] = pageMetas
            itemsByVaultRoot[vault.id] = items
            pendingError = nil
        } catch {
            pagesByVaultRoot[vault.id] = []
            itemsByVaultRoot[vault.id] = []
            pendingError = error
        }
    }

    // MARK: - Reorder (v0.2.8.0)

    /// Reorders Pages within `collection`. Matches the SwiftUI
    /// `.onMove(perform:)` signature. New ID order persists to the parent
    /// Collection's `_collection.json` sidecar.
    func reorderPages(
        in collection: Pommora.Collection,
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        var arr = pagesByCollection[collection.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        pagesByCollection[collection.id] = arr
        do {
            try OrderPersister.setPageOrder(arr.map(\.id), in: collection)
        } catch {
            self.pendingError = error
        }
    }

    /// Reorders Pages at the root of `vault`. New ID order persists to the
    /// Vault's `_vault.json` sidecar.
    func reorderPages(
        inVault vault: Vault,
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        var arr = pagesByVaultRoot[vault.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        pagesByVaultRoot[vault.id] = arr
        do {
            try OrderPersister.setPageOrder(arr.map(\.id), inVault: vault, nexus: nexus)
        } catch {
            self.pendingError = error
        }
    }
}
