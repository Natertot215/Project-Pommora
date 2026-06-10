import Foundation
import Testing

@testable import Pommora

/// Unit coverage for the V9 open-routing (`PageOpenRouter`): the pure
/// `open_in` destination logic including the edit-conflict guard, and the
/// performing `routeOpen` overload driven through a spy `openPreview` closure
/// (the real call sites hand it `openWindow(id: "page-preview", value:)`).
/// Window behavior itself (dedupe, focus, child attachment) is system-owned
/// and not unit-testable here.
@MainActor
@Suite("PageOpenRouter")
struct PageOpenRouterTests {

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

    // MARK: - destination (pure routing + the edit-conflict guard)

    @Test(".window vault routes to the detail pane")
    func windowRoutesToDetailPane() {
        let vault = makeVault(openIn: .window)
        let page = makePage()
        #expect(
            PageOpenRouter.destination(for: vault, page: page, currentSelection: .none)
                == .detailPane)
    }

    @Test("unset open_in defaults to .window (detail pane)")
    func nilOpenInDefaultsToWindow() {
        let vault = makeVault(openIn: nil)
        let page = makePage()
        #expect(
            PageOpenRouter.destination(for: vault, page: page, currentSelection: .none)
                == .detailPane)
    }

    @Test(".compact vault routes to a preview window")
    func compactRoutesToPreviewCard() {
        let vault = makeVault(openIn: .compact)
        let page = makePage()
        #expect(
            PageOpenRouter.destination(for: vault, page: page, currentSelection: .none)
                == .previewCard)
    }

    @Test("edit-conflict guard: a page shown in the main pane never previews")
    func conflictGuardSuppresses() {
        let vault = makeVault(openIn: .compact)
        let page = makePage()
        #expect(
            PageOpenRouter.destination(for: vault, page: page, currentSelection: .page(page))
                == .suppressed)
    }

    @Test("a DIFFERENT page in the main pane does not trip the guard")
    func differentPaneDoesNotSuppress() {
        let vault = makeVault(openIn: .compact)
        let shown = makePage(title: "Shown")
        let tapped = makePage(title: "Tapped")
        #expect(
            PageOpenRouter.destination(for: vault, page: tapped, currentSelection: .page(shown))
                == .previewCard)
    }

    // MARK: - routeOpen (the shared open-path: sidebar + detail-pane tables)

    @Test("routeOpen on a .compact vault opens a preview ref and leaves the selection alone")
    func routeOpenCompactOpensPreview() {
        let vault = makeVault(openIn: .compact)
        let page = makePage()
        var selection = SidebarSelection.pageType(vault)
        var opened: [PageRef] = []

        let routed = PageOpenRouter.routeOpen(
            page, vault: vault, collection: nil, selection: &selection
        ) { opened.append($0) }

        #expect(routed == .previewCard)
        #expect(opened == [PageRef(page: page, inVaultRoot: vault)])
        #expect(selection == .pageType(vault))
    }

    @Test("routeOpen carries the collection into the preview ref")
    func routeOpenCarriesCollection() {
        let vault = makeVault(openIn: .compact)
        let collection = PageCollection(
            id: ULID.generate(), typeID: vault.id, title: "Set",
            folderURL: URL(fileURLWithPath: "/tmp/Vault/Set"), modifiedAt: Date()
        )
        let page = makePage()
        var selection = SidebarSelection.collection(collection)
        var opened: [PageRef] = []

        PageOpenRouter.routeOpen(
            page, vault: vault, collection: collection, selection: &selection
        ) { opened.append($0) }

        #expect(opened == [PageRef(page: page, in: collection, vault: vault)])
    }

    @Test("routeOpen on a .window vault selects into the detail pane, no preview")
    func routeOpenWindowSelects() {
        let vault = makeVault(openIn: .window)
        let page = makePage()
        var selection = SidebarSelection.none
        var opened: [PageRef] = []

        let routed = PageOpenRouter.routeOpen(
            page, vault: vault, collection: nil, selection: &selection
        ) { opened.append($0) }

        #expect(routed == .detailPane)
        #expect(opened.isEmpty)
        #expect(selection == .page(page))
    }

    @Test("routeOpen suppresses when the tapped page already fills the main pane")
    func routeOpenSuppressedNoOps() {
        let vault = makeVault(openIn: .compact)
        let page = makePage()
        var selection = SidebarSelection.page(page)
        var opened: [PageRef] = []

        let routed = PageOpenRouter.routeOpen(
            page, vault: vault, collection: nil, selection: &selection
        ) { opened.append($0) }

        #expect(routed == .suppressed)
        #expect(opened.isEmpty)
        #expect(selection == .page(page))
    }
}
