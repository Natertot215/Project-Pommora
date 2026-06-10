import Foundation
import Testing

@testable import Pommora

/// Unit coverage for the `PagePreview` open-cards state (PagesV2 P5): open /
/// dedupe-focus / close / cascade / bring-to-front, plus the pure open-in
/// routing (`PreviewStack.destination`) including the V8 edit-conflict guard.
@MainActor
@Suite("PreviewStack")
struct PreviewStackTests {

    // MARK: - Fixtures

    private func makePage(id: String = ULID.generate(), title: String = "Note") -> PageMeta {
        PageMeta(
            id: id,
            title: title,
            url: URL(fileURLWithPath: "/tmp/\(title).md"),
            frontmatter: PageFrontmatter(
                id: id, icon: nil,
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: Date()
            )
        )
    }

    private func makeVault(openIn: OpenInMode? = nil) -> PageType {
        PageType(
            id: ULID.generate(), title: "Vault", icon: nil,
            properties: [], views: [], modifiedAt: Date(),
            openIn: openIn
        )
    }

    // MARK: - Open / cascade

    @Test("open appends a card at min size with cascade placement (+24,+24 per open card)")
    func openCascades() {
        let stack = PreviewStack()
        let vault = makeVault(openIn: .compact)

        stack.open(makePage(title: "A"), vault: vault, collection: nil)
        stack.open(makePage(title: "B"), vault: vault, collection: nil)
        stack.open(makePage(title: "C"), vault: vault, collection: nil)

        #expect(stack.cards.count == 3)
        let base = PreviewStack.baseOrigin
        let step = PreviewStack.cascadeStep
        #expect(stack.cards[0].position == base)
        #expect(stack.cards[1].position == CGPoint(x: base.x + step, y: base.y + step))
        #expect(stack.cards[2].position == CGPoint(x: base.x + 2 * step, y: base.y + 2 * step))
        #expect(stack.cards.allSatisfy { $0.size == PreviewStack.minCardSize })
    }

    @Test("open records the ref's vault/collection ids (vault-root vs collection)")
    func openBuildsRef() {
        let stack = PreviewStack()
        let vault = makeVault(openIn: .compact)
        let collection = PageCollection(
            id: ULID.generate(), typeID: vault.id, title: "Set",
            folderURL: URL(fileURLWithPath: "/tmp/Vault/Set"), modifiedAt: Date()
        )
        let rootPage = makePage(title: "Root")
        let collPage = makePage(title: "Member")

        stack.open(rootPage, vault: vault, collection: nil)
        stack.open(collPage, vault: vault, collection: collection)

        #expect(stack.cards[0].ref == PageRef(page: rootPage, inVaultRoot: vault))
        #expect(stack.cards[1].ref == PageRef(page: collPage, in: collection, vault: vault))
    }

    // MARK: - Dedupe-focus

    @Test("re-opening an already-previewed page focuses its existing card instead of duplicating")
    func reopenFocusesExisting() {
        let stack = PreviewStack()
        let vault = makeVault(openIn: .compact)
        let pageA = makePage(title: "A")
        let pageB = makePage(title: "B")

        stack.open(pageA, vault: vault, collection: nil)
        stack.open(pageB, vault: vault, collection: nil)
        let cardA = stack.cards[0]
        let cardB = stack.cards[1]
        #expect(cardB.z > cardA.z)

        stack.open(pageA, vault: vault, collection: nil)

        #expect(stack.cards.count == 2)
        #expect(cardA.z > cardB.z)  // focused = raised above the other card
    }

    // MARK: - Close

    @Test("close removes the card; closing twice is a no-op")
    func closeRemoves() {
        let stack = PreviewStack()
        let vault = makeVault(openIn: .compact)
        stack.open(makePage(title: "A"), vault: vault, collection: nil)
        stack.open(makePage(title: "B"), vault: vault, collection: nil)
        let card = stack.cards[0]

        stack.close(card)
        #expect(stack.cards.count == 1)
        #expect(!stack.cards.contains(where: { $0.id == card.id }))

        stack.close(card)
        #expect(stack.cards.count == 1)
    }

    // MARK: - Bring to front

    @Test("bringToFront raises the card above every other card")
    func bringToFrontRaises() {
        let stack = PreviewStack()
        let vault = makeVault(openIn: .compact)
        stack.open(makePage(title: "A"), vault: vault, collection: nil)
        stack.open(makePage(title: "B"), vault: vault, collection: nil)
        stack.open(makePage(title: "C"), vault: vault, collection: nil)
        let first = stack.cards[0]

        stack.bringToFront(first)

        #expect(stack.cards.allSatisfy { $0.id == first.id || $0.z < first.z })
    }

    @Test("bringToFront on the frontmost card leaves z untouched")
    func bringToFrontFrontmostNoOp() {
        let stack = PreviewStack()
        let vault = makeVault(openIn: .compact)
        stack.open(makePage(title: "A"), vault: vault, collection: nil)
        stack.open(makePage(title: "B"), vault: vault, collection: nil)
        let front = stack.cards[1]
        let zBefore = front.z

        stack.bringToFront(front)

        #expect(front.z == zBefore)
    }

    // MARK: - Open-in routing (incl. the V8 edit-conflict guard)

    @Test(".window vault routes to the detail pane")
    func windowRoutesToDetailPane() {
        let vault = makeVault(openIn: .window)
        let page = makePage()
        #expect(
            PreviewStack.destination(for: vault, page: page, currentSelection: .none)
                == .detailPane)
    }

    @Test("unset open_in defaults to .window (detail pane)")
    func nilOpenInDefaultsToWindow() {
        let vault = makeVault(openIn: nil)
        let page = makePage()
        #expect(
            PreviewStack.destination(for: vault, page: page, currentSelection: .none)
                == .detailPane)
    }

    @Test(".compact vault routes to a preview card")
    func compactRoutesToPreviewCard() {
        let vault = makeVault(openIn: .compact)
        let page = makePage()
        #expect(
            PreviewStack.destination(for: vault, page: page, currentSelection: .none)
                == .previewCard)
    }

    @Test("edit-conflict guard: a page shown in the main pane never previews")
    func conflictGuardSuppresses() {
        let vault = makeVault(openIn: .compact)
        let page = makePage()
        #expect(
            PreviewStack.destination(for: vault, page: page, currentSelection: .page(page))
                == .suppressed)
    }

    @Test("a DIFFERENT page in the main pane does not trip the guard")
    func differentPaneDoesNotSuppress() {
        let vault = makeVault(openIn: .compact)
        let shown = makePage(title: "Shown")
        let tapped = makePage(title: "Tapped")
        #expect(
            PreviewStack.destination(for: vault, page: tapped, currentSelection: .page(shown))
                == .previewCard)
    }

    // MARK: - routeOpen (the shared open-path: sidebar + detail-pane tables)

    @Test("routeOpen on a .compact vault opens a card and leaves the selection alone")
    func routeOpenCompactOpensCard() {
        let stack = PreviewStack()
        let vault = makeVault(openIn: .compact)
        let page = makePage()
        var selection = SidebarSelection.pageType(vault)

        let routed = stack.routeOpen(page, vault: vault, collection: nil, selection: &selection)

        #expect(routed == .previewCard)
        #expect(stack.cards.count == 1)
        #expect(selection == .pageType(vault))
    }

    @Test("routeOpen on a .window vault selects into the detail pane, no card")
    func routeOpenWindowSelects() {
        let stack = PreviewStack()
        let vault = makeVault(openIn: .window)
        let page = makePage()
        var selection = SidebarSelection.none

        let routed = stack.routeOpen(page, vault: vault, collection: nil, selection: &selection)

        #expect(routed == .detailPane)
        #expect(stack.cards.isEmpty)
        #expect(selection == .page(page))
    }

    @Test("routeOpen suppresses when the tapped page already fills the main pane")
    func routeOpenSuppressedNoOps() {
        let stack = PreviewStack()
        let vault = makeVault(openIn: .compact)
        let page = makePage()
        var selection = SidebarSelection.page(page)

        let routed = stack.routeOpen(page, vault: vault, collection: nil, selection: &selection)

        #expect(routed == .suppressed)
        #expect(stack.cards.isEmpty)
        #expect(selection == .page(page))
    }
}
