import Foundation
import Observation
import SwiftUI

/// One open `PagePreview` card: a rename-safe `PageRef` plus the card's live
/// geometry (top-leading origin within the overlay host) and stacking order.
///
/// A per-card `@Observable` class (not a struct inside `PreviewStack.cards`)
/// so a 60fps drag/resize of one card invalidates only that card's view —
/// mutating an element of an observed array would re-render every open card.
@MainActor
@Observable
final class PreviewCard: Identifiable {
    /// Stable id-based reference (page/vault/collection ULIDs) — survives
    /// renames and re-resolves against the live managers on every load.
    let ref: PageRef
    /// Top-leading origin inside the overlay host, clamped to its bounds.
    var position: CGPoint
    /// Collapsed (no-inspector) card size; the inspector pane widens the
    /// rendered card beyond this without touching it.
    var size: CGSize
    /// Stacking order — higher draws on top. Monotonic, assigned by
    /// `PreviewStack.bringToFront`.
    var z: Double

    /// One card per page: identity is the page's ULID, so re-opening an
    /// already-previewed page dedupes to its existing card.
    var id: String { ref.pageID }

    init(ref: PageRef, position: CGPoint, size: CGSize, z: Double) {
        self.ref = ref
        self.position = position
        self.size = size
        self.z = z
    }
}

/// Where a sidebar page-tap routes, per the page's vault `open_in` mode (V8).
enum PageOpenDestination: Equatable {
    /// `.window` vault (or unset) — render in the main detail pane.
    case detailPane
    /// `.compact` vault — open (or focus) a `PagePreview` card.
    case previewCard
    /// `.compact` vault but the page is currently shown in the main detail
    /// pane — the V8 edit-conflict guard: a main-pane page never previews.
    case suppressed
}

/// Observable open-cards state for the in-window `PagePreview` overlay (V8
/// primitive). Owned by `NexusEnvironment` (one stack per open Nexus — cards
/// reference pages of that Nexus and die with it on Nexus switch) and injected
/// through the single `.injectNexusEnvironment(_:)` modifier (quirk #15).
@MainActor
@Observable
final class PreviewStack {
    /// Minimum (and initial, collapsed) card size — per the Figma capture.
    static let minCardSize = CGSize(width: 475, height: 475)
    /// Cascade offset applied per already-open card on open (+24, +24).
    static let cascadeStep: CGFloat = 24
    /// Top-leading origin of the first card inside the overlay host.
    static let baseOrigin = CGPoint(x: 32, y: 32)

    private(set) var cards: [PreviewCard] = []
    /// Monotonic z counter; `bringToFront` assigns-and-bumps.
    private var nextZ: Double = 1

    /// Opens a preview card for `page`, cascading from `baseOrigin` by
    /// `cascadeStep` per already-open card. Re-opening an already-previewed
    /// page focuses (brings to front) its existing card instead of duplicating.
    func open(_ page: PageMeta, vault: PageType, collection: PageCollection?) {
        if let existing = cards.first(where: { $0.id == page.id }) {
            bringToFront(existing)
            return
        }
        let ref =
            collection.map { PageRef(page: page, in: $0, vault: vault) }
            ?? PageRef(page: page, inVaultRoot: vault)
        let cascade = Self.cascadeStep * CGFloat(cards.count)
        let card = PreviewCard(
            ref: ref,
            position: CGPoint(x: Self.baseOrigin.x + cascade, y: Self.baseOrigin.y + cascade),
            size: Self.minCardSize,
            z: nextZ
        )
        nextZ += 1
        cards.append(card)
    }

    /// Removes `card` from the overlay. No-op if it's already gone.
    func close(_ card: PreviewCard) {
        cards.removeAll { $0.id == card.id }
    }

    /// Raises `card` above every other open card. No-op when it's already
    /// frontmost (avoids a pointless observation fire per drag-start).
    func bringToFront(_ card: PreviewCard) {
        guard cards.contains(where: { $0.z > card.z }) else { return }
        card.z = nextZ
        nextZ += 1
    }

    /// Routes a page-tap per the vault's `open_in` mode, including the V8
    /// edit-conflict guard (a page shown in the main detail pane never opens
    /// as a preview). Pure + static so the routing is unit-testable without
    /// bootstrapping the sidebar.
    static func destination(
        for vault: PageType,
        page: PageMeta,
        currentSelection: SidebarSelection
    ) -> PageOpenDestination {
        switch vault.openIn ?? .window {
        case .window:
            return .detailPane
        case .compact:
            if case .page(let shown) = currentSelection, shown.id == page.id {
                return .suppressed
            }
            return .previewCard
        }
    }
}

// MARK: - Shared open-routing (every page-tap surface)

extension PreviewStack {
    /// The ONE open-path for a page-tap: routes per the vault's `open_in`
    /// mode and performs the destination — `.detailPane` selects into the
    /// main pane, `.previewCard` opens (or focuses) a card WITHOUT moving
    /// the selection, `.suppressed` is the V8 edit-conflict guard no-op.
    /// Shared by the sidebar and the detail-pane tables so the surfaces
    /// can't drift. Returns the routed destination for call-site chrome
    /// (the sidebar snaps its List highlight back on non-pane routes).
    @discardableResult
    func routeOpen(
        _ page: PageMeta,
        vault: PageType,
        collection: PageCollection?,
        selection: inout SidebarSelection
    ) -> PageOpenDestination {
        let destination = Self.destination(for: vault, page: page, currentSelection: selection)
        switch destination {
        case .detailPane:
            let resolved = SidebarSelection.page(page)
            if selection != resolved { selection = resolved }
        case .previewCard:
            open(page, vault: vault, collection: collection)
        case .suppressed:
            break
        }
        return destination
    }

    /// Parent-resolving variant for call sites that only hold the page
    /// (sidebar rows, vault-detail rows that mix root and collection pages).
    /// An unresolvable parent (page deleted mid-tap) falls back to the
    /// detail pane, matching the pre-V8 behavior.
    @discardableResult
    func routeOpen(
        _ page: PageMeta,
        selection: inout SidebarSelection,
        content: PageContentManager,
        vaultManager: PageTypeManager
    ) -> PageOpenDestination {
        guard let parent = content.resolveParent(for: page, pageTypeManager: vaultManager) else {
            let resolved = SidebarSelection.page(page)
            if selection != resolved { selection = resolved }
            return .detailPane
        }
        return routeOpen(page, vault: parent.vault, collection: parent.collection, selection: &selection)
    }
}
