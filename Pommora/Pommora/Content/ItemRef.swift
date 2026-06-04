import Foundation

/// Stable identifier for an open Item Window scene (T4.3). Carries only IDs —
/// rename-safe; window state survives file renames + moves within the same Item
/// Type / Set. Codable + Hashable so it can drive a `WindowGroup(for: ItemRef.self)`.
/// Resolves to the live entities via the managers (mirrors PageRef's resolver shape).
struct ItemRef: Codable, Hashable, Sendable {
    let itemID: String
    let typeID: String
    /// `nil` = type-root Item (directly inside the Item Type folder, not in a
    /// Set sub-folder).
    let collectionID: String?
}

/// Reverse lookup: given an Item's ID, find its owning Item Type + (optional)
/// parent Set by scanning the live managers. The inverse of `ItemRef.resolve`
/// (which goes ref → entities); this goes Item → ref IDs so an open-action can
/// build an `ItemRef` from nothing but the `Item`. Single source for the scan so
/// the open path doesn't re-implement it inline.
enum ItemLocationResolver {
    /// The IDs needed to build an `ItemRef` for `itemID`. `collectionID` is `nil`
    /// for a type-root Item; non-`nil` when the Item lives inside a Set.
    struct Location {
        let typeID: String
        let collectionID: String?
    }

    @MainActor
    static func locate(
        itemID: String,
        itemTypeManager: ItemTypeManager,
        itemContentManager: ItemContentManager
    ) -> Location? {
        for type in itemTypeManager.types {
            if itemContentManager.items(in: type).contains(where: { $0.id == itemID }) {
                return Location(typeID: type.id, collectionID: nil)
            }
            for collection in itemTypeManager.itemCollections(in: type)
            where itemContentManager.items(in: collection).contains(where: { $0.id == itemID }) {
                return Location(typeID: type.id, collectionID: collection.id)
            }
        }
        return nil
    }
}

extension ItemRef {
    /// Resolve to live Item + ItemType + ItemCollection via the running managers.
    /// Returns `nil` if any link in the chain is missing — e.g., the Item Type was
    /// deleted while a floating window was open, or the Item wasn't loaded yet
    /// (`ItemContentManager` loads lazily; T4.3's scene root triggers the load and
    /// handles a transient nil — no loading happens here).
    @MainActor
    func resolve(
        itemTypeManager: ItemTypeManager,
        itemContentManager: ItemContentManager
    ) -> (Item, ItemType, ItemCollection?)? {
        guard let itemType = itemTypeManager.types.first(where: { $0.id == typeID }) else {
            return nil
        }
        if let collectionID {
            guard
                let collection = itemTypeManager.itemCollections(in: itemType)
                    .first(where: { $0.id == collectionID }),
                let item = itemContentManager.items(in: collection)
                    .first(where: { $0.id == itemID })
            else { return nil }
            return (item, itemType, collection)
        } else {
            guard
                let item = itemContentManager.items(in: itemType)
                    .first(where: { $0.id == itemID })
            else { return nil }
            return (item, itemType, nil)
        }
    }
}
