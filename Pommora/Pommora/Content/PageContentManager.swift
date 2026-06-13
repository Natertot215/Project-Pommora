import Foundation
import GRDB
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
    /// PageSet-scoped Pages keyed by PageSet.id.
    var pagesBySet: [String: [PageMeta]] = [:]
    var pendingError: (any Error)?

    // nexus + contextProvider used by the +CRUD extension. Internal (not
    // private) so the extension can read them across the file boundary.
    let nexus: Nexus
    let contextProvider: @MainActor () -> NexusContext

    /// Injected by NexusManager in Phase E.7. Nil until wired; CRUD methods
    /// call it post-commit as a best-effort non-fatal write (filesystem is canonical).
    var indexUpdater: IndexUpdater?

    /// Injected by NexusEnvironment. Nil in test harnesses that don't wire
    /// navigation; rename refreshes their denormalized title caches when present.
    var pinnedManager: PinnedManager?
    var recentsManager: RecentsManager?

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

    func pages(in set: PageSet) -> [PageMeta] {
        pagesBySet[set.id] ?? []
    }

    // MARK: - Resolvers

    /// Find the PageType (and optionally PageCollection + PageSet) that a
    /// `PageMeta` lives in. Works regardless of whether the vault's pages have
    /// been loaded into the sidebar.
    ///
    /// Primary path: index lookup by page ID → type/collection/set IDs → in-memory objects.
    /// Fallback (no index): URL prefix matching against vault/collection/set folder paths.
    ///
    /// `pageSetManager` is optional for call sites that don't care about Set
    /// membership; without it `set` resolves nil even for Set pages.
    func resolveParent(
        for page: PageMeta, pageTypeManager: PageTypeManager, pageSetManager: PageSetManager? = nil
    )
        -> (vault: PageType, collection: PageCollection?, set: PageSet?)?
    {
        if let index = indexUpdater?.index,
            let result = resolveParentFromIndex(
                pageID: page.id, pageTypeManager: pageTypeManager,
                pageSetManager: pageSetManager, index: index)
        {
            return result
        }
        return resolveParentByURL(
            page.url, pageTypeManager: pageTypeManager, pageSetManager: pageSetManager)
    }

    /// Index-based parent resolution: queries page_type_id / page_collection_id /
    /// page_set_id directly, then matches them to the in-memory objects.
    private func resolveParentFromIndex(
        pageID: String, pageTypeManager: PageTypeManager, pageSetManager: PageSetManager?,
        index: PommoraIndex
    ) -> (vault: PageType, collection: PageCollection?, set: PageSet?)? {
        guard
            let row = try? index.dbQueue.read({ db in
                try Row.fetchOne(
                    db, sql: "SELECT page_type_id, page_collection_id, page_set_id FROM pages WHERE id = ?",
                    arguments: [pageID])
            })
        else { return nil }
        let typeID: String = row["page_type_id"]
        let collectionID: String? = row["page_collection_id"]
        let setID: String? = row["page_set_id"]
        guard let vault = pageTypeManager.types.first(where: { $0.id == typeID })
        else { return nil }
        if let collID = collectionID,
            let coll = pageTypeManager.pageCollections(in: vault).first(where: { $0.id == collID })
        {
            let set = setID.flatMap { sid in
                pageSetManager?.pageSets(in: coll).first { $0.id == sid }
            }
            return (vault, coll, set)
        }
        return (vault, nil, nil)
    }

    /// URL-based fallback when no index is available. All PageTypes are loaded at
    /// launch so folder-path prefix matching is always complete.
    private func resolveParentByURL(
        _ pageURL: URL, pageTypeManager: PageTypeManager, pageSetManager: PageSetManager?
    ) -> (vault: PageType, collection: PageCollection?, set: PageSet?)? {
        let canonical = pageURL.standardizedFileURL.path
        for pageType in pageTypeManager.types {
            let vaultPath = folderURL(for: pageType).standardizedFileURL.path + "/"
            guard canonical.hasPrefix(vaultPath) else { continue }
            for collection in pageTypeManager.pageCollections(in: pageType) {
                let collPath = collection.folderURL.standardizedFileURL.path + "/"
                guard canonical.hasPrefix(collPath) else { continue }
                if let pageSetManager {
                    for set in pageSetManager.pageSets(in: collection) {
                        let setPath = set.folderURL.standardizedFileURL.path + "/"
                        if canonical.hasPrefix(setPath) { return (pageType, collection, set) }
                    }
                }
                return (pageType, collection, nil)
            }
            return (pageType, nil, nil)
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
    /// recursively through sub-folders EXCEPT those that are themselves
    /// PageSets — those roll up under `loadAll(for: set)` instead. Other
    /// sub-folders aren't recognized containers — their files roll up into
    /// this PageCollection (Obsidian-parity for adopted folder structures).
    ///
    /// Pages use the lenient loader so adopted `.md` files without Pommora
    /// frontmatter still surface; missing `id` is synthesized deterministically
    /// from the file's path relative to the Nexus root (stable across launches,
    /// not written back until the user edits).
    func loadAll(for collection: PageCollection) async {
        let nexusRoot = nexus.rootURL
        // Discover PageSet sub-folders by sidecar presence so we exclude
        // their subtrees from the Collection walk — same shape as the
        // Type-root walk's PageCollection exclusion below.
        let allSubs = (try? Filesystem.childFolders(of: collection.folderURL)) ?? []
        let setFolders = allSubs.filter { sub in
            Filesystem.fileExists(at: sub.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        }
        let excludedSetFolders = Set(setFolders.map { $0.standardizedFileURL })
        do {
            let pageFiles = try Filesystem.descendantFiles(
                of: collection.folderURL,
                excluding: excludedSetFolders
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
            let freshOrder = Self.freshPageOrder(
                from: collection.folderURL.appendingPathComponent(
                    NexusPaths.pageCollectionSidecarFilename),
                as: PageCollection.self, fallback: collection.pageOrder)
            let pageMetas = OrderResolver.resolve(
                unsortedPages,
                persistedOrder: freshOrder,
                titleKeyPath: \PageMeta.title
            )

            pagesByCollection[collection.id] = pageMetas
            pendingError = nil
        } catch {
            pagesByCollection[collection.id] = []
            pendingError = error
        }
    }

    // MARK: - Load (PageSet-scoped)

    /// Loads every `.md` Page inside `set.folderURL`, descending recursively
    /// through sub-folders. A Set has no recognized sub-containers, so deeper
    /// folders roll up into this PageSet — mirroring the PageCollection walk.
    func loadAll(for set: PageSet) async {
        let nexusRoot = nexus.rootURL
        do {
            let pageFiles = try Filesystem.descendantFiles(of: set.folderURL) { url in
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
            let freshOrder = Self.freshPageOrder(
                from: set.folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename),
                as: PageSet.self, fallback: set.pageOrder)
            let pageMetas = OrderResolver.resolve(
                unsortedPages,
                persistedOrder: freshOrder,
                titleKeyPath: \PageMeta.title
            )

            pagesBySet[set.id] = pageMetas
            pendingError = nil
        } catch {
            pagesBySet[set.id] = []
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
                excluding: excludedCollectionFolders,
                folderFilter: FolderFilter.load(for: nexus)
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
            // `page_order` can drift from the passed snapshot when a sibling
            // drag-reorder wrote it straight to disk (reorderPages → OrderPersister)
            // without updating the in-memory PageType. Re-read the sidecar so a
            // re-entry resolve reflects the persisted order instead of reverting to
            // the stale snapshot. Files are canonical.
            let freshOrder = Self.freshPageOrder(
                from: folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename),
                as: PageType.self, fallback: pageType.pageOrder)
            let pageMetas = OrderResolver.resolve(
                unsortedPages,
                persistedOrder: freshOrder,
                titleKeyPath: \PageMeta.title
            )

            pagesByTypeRoot[pageType.id] = pageMetas
            pendingError = nil
        } catch {
            pagesByTypeRoot[pageType.id] = []
            pendingError = error
        }
    }

    /// Re-reads the canonical `page_order` from a container sidecar so a
    /// re-entry resolve reflects a drag-reorder that wrote straight to disk
    /// without updating the in-memory snapshot (files are canonical). Falls back
    /// to `fallback` when the sidecar can't be read. One source for the three
    /// `loadAll` loaders (Collection / Set / Type) — see the WRITE-side
    /// `writeStoredPages` PageParent switch for the mirror.
    private static func freshPageOrder<S: PageOrderSidecar>(
        from sidecarURL: URL, as: S.Type, fallback: [String]?
    ) -> [String]? {
        (try? S.load(from: sidecarURL))?.pageOrder ?? fallback
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

    /// Reorders Pages within `set`. New ID order persists to the parent
    /// PageSet's `_pageset.json` sidecar.
    func reorderPages(
        in set: PageSet,
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        var arr = pagesBySet[set.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        pagesBySet[set.id] = arr
        do {
            try OrderPersister.setPageOrder(arr.map(\.id), in: set)
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

    // MARK: - Reorder by id (group-subset-safe)

    /// Reorders Pages within `parent` by MOVING IDS + an ANCHOR id, resolving the
    /// stored-array offsets internally. The view's drag path computes indices in
    /// the FILTERED / BUCKETED group subset, which can differ from this stored
    /// container array under property-grouping or an active filter — so it hands
    /// off ids instead of offsets, and this overload rebuilds the order against
    /// the canonical stored array.
    ///
    /// `movingIDs` are placed (in their given order) immediately BEFORE
    /// `anchorID`; `anchorID == nil` appends them at the container's end. Ids not
    /// present in the stored array are ignored. Persists to the parent sidecar.
    func reorderPages(in parent: PageParent, movingIDs: [String], before anchorID: String?) {
        let current = storedPages(in: parent)
        let newOrderIDs = Self.reorderedIDs(
            current: current.map(\.id), movingIDs: movingIDs, before: anchorID)
        guard newOrderIDs != current.map(\.id) else { return }
        let byID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let result = newOrderIDs.compactMap { byID[$0] }
        writeStoredPages(result, in: parent)
    }

    /// Pure id-space reorder: place `movingIDs` (in given order) immediately
    /// BEFORE `anchorID` within `current`, or append them when `anchorID` is nil
    /// / absent. Ids not in `current` are dropped. The reorder-by-id commit's
    /// container-space translation lives here so it's unit-testable without disk.
    static func reorderedIDs(
        current: [String], movingIDs: [String], before anchorID: String?
    ) -> [String] {
        let moving = Set(movingIDs)
        guard !moving.isEmpty else { return current }
        let currentSet = Set(current)
        // De-duplicate while preserving order so a defensive duplicate id never
        // double-inserts the moving block.
        var seen = Set<String>()
        let ordered = movingIDs.filter { current.contains($0) && seen.insert($0).inserted }
        let remaining = current.filter { !moving.contains($0) }

        // Resolve the effective insertion anchor to a NON-moving id: when
        // `anchorID` is itself a moving id (drop onto the selection's own
        // top-half / own member), insertion would otherwise fall through to
        // append-at-end. Use the first non-moving id at-or-after the anchor's
        // index in `current` (nil → append).
        let effectiveAnchor: String?
        if let anchorID, currentSet.contains(anchorID),
            let anchorIndex = current.firstIndex(of: anchorID)
        {
            effectiveAnchor = current[anchorIndex...].first { !moving.contains($0) }
        } else {
            effectiveAnchor = nil
        }

        var result: [String] = []
        var inserted = false
        for id in remaining {
            if !inserted, id == effectiveAnchor {
                result.append(contentsOf: ordered)
                inserted = true
            }
            result.append(id)
        }
        if !inserted { result.append(contentsOf: ordered) }
        return result
    }

    /// The stored container array for a `PageParent` (the canonical order, not a
    /// group subset).
    private func storedPages(in parent: PageParent) -> [PageMeta] {
        switch parent {
        case .collection(let coll, _): return pagesByCollection[coll.id] ?? []
        case .set(let set, _, _): return pagesBySet[set.id] ?? []
        case .vaultRoot(let type): return pagesByTypeRoot[type.id] ?? []
        }
    }

    /// Commit a reordered container array in memory + persist to the parent sidecar.
    private func writeStoredPages(_ pages: [PageMeta], in parent: PageParent) {
        do {
            switch parent {
            case .collection(let coll, _):
                pagesByCollection[coll.id] = pages
                try OrderPersister.setPageOrder(pages.map(\.id), in: coll)
            case .set(let set, _, _):
                pagesBySet[set.id] = pages
                try OrderPersister.setPageOrder(pages.map(\.id), in: set)
            case .vaultRoot(let type):
                pagesByTypeRoot[type.id] = pages
                try OrderPersister.setPageOrder(pages.map(\.id), inVault: type, nexus: nexus)
            }
        } catch {
            self.pendingError = error
        }
    }
}
