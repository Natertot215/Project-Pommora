import SwiftUI

/// Where a page-tap routes, per the page's vault `open_in` mode.
enum PageOpenDestination: Equatable {
    /// `.window` vault (or unset) — render in the main detail pane.
    case detailPane
    /// `.compact` vault — open (or focus) the page's PagePreview window.
    case previewCard
    /// `.compact` vault but the page is currently shown in the main detail
    /// pane — the edit-conflict guard: a main-pane page never previews.
    case suppressed
}

/// The ONE open-path for a page-tap, shared by the sidebar and the
/// detail-pane tables so the surfaces can't drift. `.detailPane` selects into
/// the main pane; `.previewCard` hands a rename-safe `PageRef` to
/// `openPreview` (call sites pass `{ openPagePreview($0) }` — a closure, so the
/// routing stays unit-testable); `.suppressed` is the edit-conflict no-op.
@MainActor
enum PageOpenRouter {
    /// Pure routing per the vault's `open_in` mode, including the
    /// edit-conflict guard. Static so it's unit-testable without
    /// bootstrapping the sidebar.
    static func destination(
        for pageCollection: PageCollection,
        page: PageMeta,
        currentSelection: SidebarSelection
    ) -> PageOpenDestination {
        switch pageCollection.openIn ?? .window {
        case .window:
            return .detailPane
        case .compact:
            if case .page(let shown) = currentSelection, shown.id == page.id {
                return .suppressed
            }
            return .previewCard
        }
    }

    /// Routes AND performs the destination for a tap whose parent containers
    /// are known (collection-detail tables, the sidebar's resolved rows).
    @discardableResult
    static func routeOpen(
        _ page: PageMeta,
        pageCollection: PageCollection,
        collection: PageSet?,
        set: PageSet?,
        selection: inout SidebarSelection,
        openPreview: (PageRef) -> Void
    ) -> PageOpenDestination {
        let routed = destination(for: pageCollection, page: page, currentSelection: selection)
        switch routed {
        case .detailPane:
            let resolved = SidebarSelection.page(page)
            if selection != resolved { selection = resolved }
        case .previewCard:
            let ref: PageRef =
                switch (collection, set) {
                case (let collection?, let set?):
                    PageRef(page: page, in: set, collection: collection, pageCollection: pageCollection)
                case (let collection?, nil):
                    PageRef(page: page, in: collection, pageCollection: pageCollection)
                case (nil, _):
                    PageRef(page: page, inCollectionRoot: pageCollection)
                }
            openPreview(ref)
        case .suppressed:
            break
        }
        return routed
    }

    /// Parent-resolving variant for call sites that only hold the page
    /// (sidebar rows, vault-detail rows that mix root and collection pages).
    /// An unresolvable parent (page deleted mid-tap) falls back to the
    /// detail pane.
    @discardableResult
    static func routeOpen(
        _ page: PageMeta,
        selection: inout SidebarSelection,
        content: PageContentManager,
        collectionManager: PageCollectionManager,
        setManager: PageSetManager,
        openPreview: (PageRef) -> Void
    ) -> PageOpenDestination {
        guard
            let parent = content.resolveParent(
                for: page, collectionManager: collectionManager, pageSetManager: setManager)
        else {
            let resolved = SidebarSelection.page(page)
            if selection != resolved { selection = resolved }
            return .detailPane
        }
        return routeOpen(
            page, pageCollection: parent.pageCollection, collection: parent.collection, set: parent.set,
            selection: &selection, openPreview: openPreview)
    }
}
