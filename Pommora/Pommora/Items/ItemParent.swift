import Foundation

/// Where an Item lives inside an Item Type. The spec allows Items to sit
/// directly in an Item Type's root folder OR inside an ItemCollection
/// sub-folder; this enum lets sidebar rows and sheets route create/rename/delete
/// calls to the correct ItemContentManager overload without leaking that
/// branching into UI code. Items-side mirror of `PageParent`.
enum ItemParent: Hashable {
    case collection(ItemCollection, type: ItemType)
    case typeRoot(ItemType)
}
