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

extension DetailRow {
    /// Recents/Pinned wire-record for this row. Leaf content (Page / Item) maps
    /// to a ref; containers (Collection / Set) return nil — they aren't pinned
    /// from the detail-pane row menus. Single source for all four detail views.
    var stateRef: EntityStateRef? {
        switch kind {
        case .page(let p): return EntityStateRef(kind: .page, id: p.id, title: p.title)
        case .item(let i): return EntityStateRef(kind: .item, id: i.id, title: i.title)
        case .collection, .itemCollection: return nil
        }
    }

    @MainActor var isPinned: Bool {
        guard let ref = stateRef else { return false }
        return AppGlobals.pinnedManager?.contains(ref) ?? false
    }

    @MainActor func togglePin() {
        guard let ref = stateRef else { return }
        AppGlobals.pinnedManager?.toggle(ref)
    }
}
