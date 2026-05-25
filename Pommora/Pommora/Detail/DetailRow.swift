import Foundation

/// Hierarchical row model consumed by SwiftUI `Table(_:children:)`.
/// `children == nil` → leaf row (no disclosure triangle).
/// `children == []`  → expandable but empty.
/// `children == [...]` → expandable with N nested rows.
struct DetailRow: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case collection(PageCollection)
        case page(PageMeta)
        case item(Item)
        case itemCollection(ItemCollection)
    }

    let id: String
    let title: String
    let kind: Kind
    let iconName: String
    let modifiedAt: Date
    let children: [DetailRow]?

    var kindLabel: String {
        switch kind {
        case .collection: return "Collection"
        case .page: return "Page"
        case .item: return "Item"
        case .itemCollection: return "Set"
        }
    }
}
