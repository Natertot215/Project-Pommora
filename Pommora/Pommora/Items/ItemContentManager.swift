import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderItems

/// Manages Items (`.json`) inside an Item Type. The spec allows Items to live
/// either directly in an Item Type's root folder or inside an ItemCollection
/// sub-folder — both are first-class. ItemCollection-scoped state and
/// type-root-scoped state are kept in parallel dictionaries to avoid
/// nullable `ItemCollection` plumbing through every CRUD signature.
///
/// All CRUD methods take the parent `ItemType` because Item validation needs
/// the Type's property schema. Property validation arrives in Phase 6 alongside
/// the wrapper-folder layout + ItemAdopter pass; v0.3.0 ships with the storage
/// + accessors + load paths only (stub-and-progressively-replace per the
/// branch quirks).
///
/// CRUD methods are split into `ItemContentManager+CRUD.swift` for legibility,
/// mirroring PageContentManager.
///
/// **ParadigmV2 (Task 5.5):** Items-side mirror of `PageContentManager`.
/// Pages stay in `PageContentManager`; this type owns Items only.
@MainActor
@Observable
final class ItemContentManager {
    /// ItemCollection-scoped Items keyed by ItemCollection.id.
    var itemsByCollection: [String: [Item]] = [:]
    /// Item-Type-root Items (directly inside the Type folder, NOT in an
    /// ItemCollection) keyed by ItemType.id.
    var itemsByTypeRoot: [String: [Item]] = [:]
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

    func items(in collection: ItemCollection) -> [Item] {
        itemsByCollection[collection.id] ?? []
    }

    func items(in itemType: ItemType) -> [Item] {
        itemsByTypeRoot[itemType.id] ?? []
    }

    // MARK: - Path helpers (Item-Type-root)

    /// ItemType.folderURL isn't a stored property — it's always derived from
    /// the nexus root + the Type's title. Centralized here so every Type-root
    /// CRUD path uses the same derivation. Internal so the +CRUD extension
    /// can call it across the file boundary.
    ///
    /// flatlayout: ItemType folders live directly at the Nexus root (no
    /// wrapper segment).
    func folderURL(for itemType: ItemType) -> URL {
        NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: itemType.title)
    }

    // MARK: - Load (ItemCollection-scoped)

    /// Loads every `.json` Item inside `collection.folderURL`, descending
    /// recursively through sub-folders. Sub-folders deeper than the locked
    /// 2-level Type/ItemCollection model aren't themselves ItemCollections —
    /// their files roll up into this ItemCollection (Obsidian-parity for
    /// adopted folder structures).
    func loadAll(for collection: ItemCollection) async {
        do {
            let itemFiles = try Filesystem.descendantFiles(of: collection.folderURL) { url in
                url.pathExtension == "json" && !url.lastPathComponent.hasPrefix("_")
            }
            let unsortedItems: [Item] = itemFiles.compactMap { try? Item.load(from: $0) }
            let items = OrderResolver.resolve(
                unsortedItems,
                persistedOrder: collection.itemOrder,
                titleKeyPath: \Item.title
            )

            itemsByCollection[collection.id] = items
            pendingError = nil
        } catch {
            itemsByCollection[collection.id] = []
            pendingError = error
        }
    }

    // MARK: - Load (Item-Type-root)

    /// Scans the Item Type root for `.json` Items, recursing into every
    /// sub-folder EXCEPT those that are themselves ItemCollections — those
    /// roll up under `loadAll(for: collection)` instead.
    func loadAll(for itemType: ItemType) async {
        let folder = folderURL(for: itemType)
        // Discover ItemCollection sub-folders by sidecar presence so we
        // exclude their subtrees from the Type-root walk.
        let allSubs = (try? Filesystem.childFolders(of: folder)) ?? []
        let collectionFolders = allSubs.filter { sub in
            Filesystem.fileExists(
                at: sub.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename)
            )
        }
        let excludedCollectionFolders = Set(collectionFolders.map { $0.standardizedFileURL })
        do {
            let itemFiles = try Filesystem.descendantFiles(
                of: folder,
                excluding: excludedCollectionFolders
            ) { url in
                url.pathExtension == "json" && !url.lastPathComponent.hasPrefix("_")
            }
            let unsortedItems: [Item] = itemFiles.compactMap { try? Item.load(from: $0) }
            let items = OrderResolver.resolve(
                unsortedItems,
                persistedOrder: itemType.itemOrder,
                titleKeyPath: \Item.title
            )

            itemsByTypeRoot[itemType.id] = items
            pendingError = nil
        } catch {
            itemsByTypeRoot[itemType.id] = []
            pendingError = error
        }
    }

    // MARK: - Reorder

    /// Reorders Items within `collection`. Matches the SwiftUI
    /// `.onMove(perform:)` signature. New ID order persists to the parent
    /// ItemCollection's `_itemcollection.json` sidecar (Phase 6 wires the persister).
    func reorderItems(
        in collection: ItemCollection,
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        var arr = itemsByCollection[collection.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        itemsByCollection[collection.id] = arr
        // OrderPersister wiring for ItemCollection lands in Phase 6 alongside
        // ItemTypeManager. The in-memory reorder above already updates the
        // visible row order; persistence catches up when the persister exists.
    }

    /// Reorders Items at the root of `itemType`. New ID order persists to the
    /// Item Type's `_itemtype.json` sidecar (Phase 6 wires the persister).
    func reorderItems(
        inType itemType: ItemType,
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        var arr = itemsByTypeRoot[itemType.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        itemsByTypeRoot[itemType.id] = arr
        // OrderPersister wiring for Item Type itemOrder lands in Phase 6.
    }
}
