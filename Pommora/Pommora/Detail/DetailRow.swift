import Foundation

/// Hierarchical row model consumed by SwiftUI `Table(_:children:)`.
/// `children == nil` → leaf row (no disclosure triangle).
/// `children == []`  → expandable but empty.
/// `children == [...]` → expandable with N nested rows.
struct DetailRow: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case collection(PageCollection)
        case set(PageSet)
        case page(PageMeta)
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
        case .set: return "Set"
        case .page: return "Page"
        }
    }
}

extension DetailRow {
    /// Recents/Pinned wire-record for this row. Leaf content (a Page) maps
    /// to a ref; containers (Collections, Sets) return nil — they aren't
    /// pinned from the detail-pane row menus. Single source for the detail views.
    var stateRef: EntityStateRef? {
        switch kind {
        case .page(let p): return EntityStateRef(kind: .page, id: p.id, title: p.title)
        case .collection, .set: return nil
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

// MARK: - Row construction

extension DetailRow {
    /// Leaf row for a Page. Shared by the PageType and PageCollection detail
    /// views — one mapping, two tables.
    static func pageRow(_ p: PageMeta) -> DetailRow {
        DetailRow(
            id: "page-\(p.id)",
            title: p.title,
            kind: .page(p),
            iconName: p.frontmatter.icon ?? "doc.text",
            modifiedAt: p.frontmatter.createdAt,
            children: nil
        )
    }

    /// Rows for a PageCollection detail table: Set rows first (each carrying
    /// its Pages as disclosure children — `[]` for an empty Set, which
    /// renders as a plain leaf row so new Sets are visible immediately),
    /// then collection-root Page rows. Pure so it's unit-testable.
    static func collectionRows(
        sets: [(set: PageSet, pages: [PageMeta])],
        rootPages: [PageMeta]
    ) -> [DetailRow] {
        let setRows = sets.map { entry in
            DetailRow(
                id: "set-\(entry.set.id)",
                title: entry.set.title,
                kind: .set(entry.set),
                iconName: entry.set.icon ?? "folder",
                modifiedAt: entry.set.modifiedAt,
                children: entry.pages.map(pageRow)
            )
        }
        return setRows + rootPages.map(pageRow)
    }
}
