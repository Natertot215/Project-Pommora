import Foundation

/// The scope a view renders in. Vault scope (PageCollection detail) spans every
/// Collection and its Sets; Collection scope (PageCollection detail) spans one
/// Collection's Sets plus its loose root pages. Drives structural grouping shape.
enum ViewScope: Equatable, Sendable {
    case pageCollection
    case collection
}

/// A resolved, render-ready band of items. The pipeline's output: fetch → filter
/// → group → sort-within-groups → `[ResolvedGroup]`. Both renderers consume this.
///
/// `children` is vault-table-only: a Collection group nests its Sets as child
/// groups (pages in no Set live in the Collection's own `items`). The gallery
/// renderer flattens via `flattenedItems` (vault scope renders ONE section level).
struct ResolvedGroup: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case structuralCollection(PageSet)
        case structuralSet(PageSet)
        case propertyBucket(value: String?)
        case ungrouped
    }

    let id: String  // container ULID / option value / "true"/"false" / "_ungrouped"
    let title: String
    let kind: Kind
    var items: [ViewItem]
    var children: [ResolvedGroup]?  // vault table only: Sets nested under a Collection group

    /// Whether the renderer should hide this group's items (header still shows).
    /// Carries the caller's collapse decision so both renderers branch identically.
    var isCollapsed: Bool

    init(
        id: String,
        title: String,
        kind: Kind,
        items: [ViewItem],
        children: [ResolvedGroup]? = nil,
        isCollapsed: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.items = items
        self.children = children
        self.isCollapsed = isCollapsed
    }

    /// Gallery flattening home (vault scope renders ONE section level): own items
    /// plus all descendants'. No page is lost when collapsing the children tree.
    var flattenedItems: [ViewItem] { items + (children ?? []).flatMap(\.flattenedItems) }
}
