import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderPages

/// Manages Pages (`.md`) inside a Page Type. The spec allows Pages to live
/// either directly in a Page Type's root folder or inside a PageCollection
/// sub-folder — both are first-class. PageCollection-scoped state and
/// type-root-scoped state are kept in parallel dictionaries to avoid
/// nullable `PageCollection` plumbing through every CRUD signature.
///
/// PageMeta = lightweight tracking value (no body in memory); full PageFile is
/// loaded on demand by the editor (post-v0.2).
///
/// All CRUD methods take the parent `PageType` because Page validation needs
/// the Type's property schema. Validation runs before every write.
///
/// CRUD methods are split into `PageContentManager+CRUD.swift` for legibility —
/// this file holds storage + accessors + load paths only.
///
/// **ParadigmV2 (Task 5.5):** Items have been moved to a parallel
/// `ItemContentManager` typed on Item + ItemType + ItemCollection. This type
/// no longer carries any Item state or methods.
@MainActor
@Observable
final class PageContentManager {
    /// PageCollection-scoped Pages keyed by PageCollection.id.
    /// Note: relaxed from `private(set)` to internal-set so the
    /// `PageContentManager+CRUD.swift` extension can mutate. Tests + UI still
    /// go through the accessor methods below; nothing outside the type reaches
    /// into the dictionaries by index.
    var pagesByCollection: [String: [PageMeta]] = [:]
    /// Page-Type-root Pages (directly inside the Type folder, NOT in a PageCollection)
    /// keyed by PageType.id.
    var pagesByTypeRoot: [String: [PageMeta]] = [:]
    /// Folder-scoped Pages (third tier on the Pages side, F.1.h) keyed by
    /// `Folder.id`. A page lives in exactly ONE of the three dicts — the on-
    /// disk parent path (with the right per-kind sidecar) determines which.
    var pagesByFolder: [String: [PageMeta]] = [:]
    var pendingError: (any Error)?

    // nexus + contextProvider used by the +CRUD extension. Internal (not
    // private) so the extension can read them across the file boundary.
    let nexus: Nexus
    let contextProvider: @MainActor () -> NexusContext

    /// Injected by NexusManager in Phase E.7. Nil until wired; CRUD methods
    /// call it post-commit as a best-effort non-fatal write (filesystem is canonical).
    var indexUpdater: IndexUpdater?

    /// Current Nexus ID — used by the drag system's cross-window guard.
    var nexusID: String { nexus.id }

    init(nexus: Nexus, contextProvider: @escaping @MainActor () -> NexusContext) {
        self.nexus = nexus
        self.contextProvider = contextProvider
    }

    // MARK: - Accessors

    func pages(in collection: PageCollection) -> [PageMeta] {
        pagesByCollection[collection.id] ?? []
    }

    func pages(in pageType: PageType) -> [PageMeta] {
        pagesByTypeRoot[pageType.id] ?? []
    }

    /// Folder-scoped page accessor (F.1.h). Pages inside a Folder appear only
    /// in `pagesByFolder[folder.id]` — never in the parent Collection's bucket
    /// (the Collection's loadAll explicitly excludes Folder sub-folders).
    func pages(in folder: Folder) -> [PageMeta] {
        pagesByFolder[folder.id] ?? []
    }

    // MARK: - Resolvers

    /// Find the PageType (and optionally PageCollection + Folder) that a
    /// `PageMeta` lives in. Returns `nil` if the Page isn't in any loaded
    /// container. Used by the editor (inspector + rename + saver
    /// construction) when only PageMeta is in hand. Brute-force O(N+M+K)
    /// walker; SQLite-backed lookup arrives with v0.4.0.
    ///
    /// Lookup order: Type-root → Folder (Collection grandparent inferred) →
    /// Collection-root. Folder check goes before Collection so a page that
    /// lives in a Folder doesn't accidentally match against the Collection's
    /// bucket (which is excluded at load anyway, but the ordering is
    /// defensive against any future load-walk regression).
    func resolveParent(
        for page: PageMeta, pageTypeManager: PageTypeManager
    )
        -> (vault: PageType, collection: PageCollection?, folder: Folder?)?
    {
        for pageType in pageTypeManager.types {
            if pages(in: pageType).contains(where: { $0.id == page.id }) {
                return (pageType, nil, nil)
            }
            for collection in pageTypeManager.pageCollections(in: pageType) {
                for folder in pageTypeManager.folders(in: collection) {
                    if pages(in: folder).contains(where: { $0.id == page.id }) {
                        return (pageType, collection, folder)
                    }
                }
                if pages(in: collection).contains(where: { $0.id == page.id }) {
                    return (pageType, collection, nil)
                }
            }
        }
        return nil
    }

    // MARK: - Path helpers (Page-Type-root)

    /// PageType.folderURL isn't a stored property — it's always derived from the
    /// nexus root + the Type's title. Centralized here so every Type-root
    /// CRUD path uses the same derivation. Internal so the +CRUD extension
    /// can call it across the file boundary.
    func folderURL(for pageType: PageType) -> URL {
        NexusPaths.vaultFolderURL(forTitle: pageType.title, in: nexus)
    }

    // MARK: - Load (PageCollection-scoped)

    /// Loads every `.md` Page inside `collection.folderURL`, descending
    /// recursively through sub-folders. Sub-folders deeper than the locked
    /// 2-level Vault/PageCollection model aren't themselves PageCollections —
    /// their files roll up into this PageCollection (Obsidian-parity for
    /// adopted folder structures).
    ///
    /// Pages use the lenient loader so adopted `.md` files without Pommora
    /// frontmatter still surface; missing `id` is synthesized deterministically
    /// from the file's path relative to the Nexus root (stable across launches,
    /// not written back until the user edits).
    func loadAll(for collection: PageCollection) async {
        let nexusRoot = nexus.rootURL
        // F.1.h — exclude Folder-tagged sub-folders from the Collection
        // walk; their pages load via `loadAll(for: folder)` instead.
        // Untagged sub-folders continue to roll up here (Obsidian-parity).
        let allSubs = (try? Filesystem.childFolders(of: collection.folderURL)) ?? []
        let folderSubs = allSubs.filter { sub in
            Filesystem.fileExists(
                at: sub.appendingPathComponent(NexusPaths.folderSidecarFilename)
            )
        }
        let excludedFolderSubs = Set(folderSubs.map { $0.standardizedFileURL })
        do {
            let pageFiles = try Filesystem.descendantFiles(
                of: collection.folderURL,
                excluding: excludedFolderSubs
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
                persistedOrder: collection.pageOrder,
                titleKeyPath: \PageMeta.title
            )

            pagesByCollection[collection.id] = pageMetas
            pendingError = nil
        } catch {
            pagesByCollection[collection.id] = []
            pendingError = error
        }
    }

    // MARK: - Load (Folder-scoped, F.1.h)

    /// Loads every `.md` Page directly inside `folder.folderURL`. Folders
    /// are terminal in the three-tier model — no nested Folders, no
    /// Collections inside Folders — so the walk is shallow (single level
    /// of `.md` children plus any untagged deep nesting which rolls up here,
    /// mirroring the Collection's roll-up semantics one level shallower).
    func loadAll(for folder: Folder) async {
        let nexusRoot = nexus.rootURL
        do {
            let pageFiles = try Filesystem.descendantFiles(of: folder.folderURL) { url in
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
                persistedOrder: folder.pageOrder,
                titleKeyPath: \PageMeta.title
            )

            pagesByFolder[folder.id] = pageMetas
            pendingError = nil
        } catch {
            pagesByFolder[folder.id] = []
            pendingError = error
        }
    }

    // MARK: - Load (Page-Type-root)

    /// Scans the Page Type root for `.md` Pages, recursing into every
    /// sub-folder EXCEPT those that are themselves PageCollections — those
    /// roll up under `loadAll(for: collection)` instead. Deep sub-folders that
    /// aren't PageCollections (depth ≥ 2) contribute their files to the Type root,
    /// matching Obsidian's "show every `.md` in the vault" semantics.
    ///
    /// Pages use the lenient loader so adopted Markdown surfaces even when
    /// it predates Pommora frontmatter.
    func loadAll(for pageType: PageType) async {
        let folder = folderURL(for: pageType)
        let nexusRoot = nexus.rootURL
        // Discover PageCollection sub-folders by sidecar presence so we exclude
        // their subtrees from the Type-root walk — their files load via
        // `loadAll(for: collection)`, not here. Avoids needing a PageTypeManager
        // handle inside PageContentManager.
        let allSubs = (try? Filesystem.childFolders(of: folder)) ?? []
        let collectionFolders = allSubs.filter { sub in
            Filesystem.fileExists(at: sub.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
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
                persistedOrder: pageType.pageOrder,
                titleKeyPath: \PageMeta.title
            )

            pagesByTypeRoot[pageType.id] = pageMetas
            pendingError = nil
        } catch {
            pagesByTypeRoot[pageType.id] = []
            pendingError = error
        }
    }

    // MARK: - Reorder (v0.2.8.0)

    /// Reorders Pages within `collection`. Matches the SwiftUI
    /// `.onMove(perform:)` signature. New ID order persists to the parent
    /// PageCollection's `_pagecollection.json` sidecar.
    func reorderPages(
        in collection: PageCollection,
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

    /// Reorders Pages at the root of `pageType`. New ID order persists to the
    /// Page Type's `_pagetype.json` sidecar.
    func reorderPages(
        inVault pageType: PageType,
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        var arr = pagesByTypeRoot[pageType.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        pagesByTypeRoot[pageType.id] = arr
        do {
            try OrderPersister.setPageOrder(arr.map(\.id), inVault: pageType, nexus: nexus)
        } catch {
            self.pendingError = error
        }
    }

    /// Reorders Pages inside `folder` (F.1.h). New ID order persists to the
    /// Folder's `_folder.json` sidecar. Folder-scoped Pages reorder
    /// independently of the parent Collection's pageOrder.
    func reorderPages(
        in folder: Folder,
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        var arr = pagesByFolder[folder.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        pagesByFolder[folder.id] = arr
        do {
            try OrderPersister.setPageOrder(arr.map(\.id), in: folder)
        } catch {
            self.pendingError = error
        }
    }
}
