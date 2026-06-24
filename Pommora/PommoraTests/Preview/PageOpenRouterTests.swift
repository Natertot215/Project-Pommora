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

    private func makeCollection(openIn: OpenInMode? = nil) -> PageCollection {
        PageCollection(
            id: ULID.generate(), title: "Vault", icon: nil,
            properties: [], views: [], modifiedAt: Date(),
            openIn: openIn
        )
    }

    // MARK: - destination (pure routing + the edit-conflict guard)

    @Test(".window vault routes to the detail pane")
    func windowRoutesToDetailPane() {
        let collection = makeCollection(openIn: .window)
        let page = makePage()
        #expect(
            PageOpenRouter.destination(for: collection, page: page, currentSelection: .none)
                == .detailPane)
    }

    @Test("unset open_in defaults to .window (detail pane)")
    func nilOpenInDefaultsToWindow() {
        let collection = makeCollection(openIn: nil)
        let page = makePage()
        #expect(
            PageOpenRouter.destination(for: collection, page: page, currentSelection: .none)
                == .detailPane)
    }

    @Test(".compact vault routes to a preview window")
    func compactRoutesToPreviewCard() {
        let collection = makeCollection(openIn: .compact)
        let page = makePage()
        #expect(
            PageOpenRouter.destination(for: collection, page: page, currentSelection: .none)
                == .previewCard)
    }

    @Test("edit-conflict guard: a page shown in the main pane never previews")
    func conflictGuardSuppresses() {
        let collection = makeCollection(openIn: .compact)
        let page = makePage()
        #expect(
            PageOpenRouter.destination(for: collection, page: page, currentSelection: .page(page))
                == .suppressed)
    }

    @Test("a DIFFERENT page in the main pane does not trip the guard")
    func differentPaneDoesNotSuppress() {
        let collection = makeCollection(openIn: .compact)
        let shown = makePage(title: "Shown")
        let tapped = makePage(title: "Tapped")
        #expect(
            PageOpenRouter.destination(for: collection, page: tapped, currentSelection: .page(shown))
                == .previewCard)
    }

    // MARK: - routeOpen (the shared open-path: sidebar + detail-pane tables)

    @Test("routeOpen on a .compact vault opens a preview ref and leaves the selection alone")
    func routeOpenCompactOpensPreview() {
        let collection = makeCollection(openIn: .compact)
        let page = makePage()
        var selection = SidebarSelection.pageCollection(collection)
        var opened: [PageRef] = []

        let routed = PageOpenRouter.routeOpen(
            page, pageCollection: collection, collection: nil, set: nil, selection: &selection
        ) { opened.append($0) }

        #expect(routed == .previewCard)
        #expect(opened == [PageRef(page: page, inCollectionRoot: collection)])
        #expect(selection == .pageCollection(collection))
    }

    @Test("routeOpen carries the collection into the preview ref")
    func routeOpenCarriesCollection() {
        let pageCollection = makeCollection(openIn: .compact)
        let collection = PageSet(
            id: ULID.generate(), parentID: pageCollection.id, title: "Set",
            folderURL: URL(fileURLWithPath: "/tmp/Vault/Set"), modifiedAt: Date()
        )
        let page = makePage()
        var selection = SidebarSelection.collection(collection)
        var opened: [PageRef] = []

        PageOpenRouter.routeOpen(
            page, pageCollection: pageCollection, collection: collection, set: nil, selection: &selection
        ) { opened.append($0) }

        #expect(opened == [PageRef(page: page, in: collection, pageCollection: pageCollection)])
    }

    @Test("routeOpen on a .window vault selects into the detail pane, no preview")
    func routeOpenWindowSelects() {
        let collection = makeCollection(openIn: .window)
        let page = makePage()
        var selection = SidebarSelection.none
        var opened: [PageRef] = []

        let routed = PageOpenRouter.routeOpen(
            page, pageCollection: collection, collection: nil, set: nil, selection: &selection
        ) { opened.append($0) }

        #expect(routed == .detailPane)
        #expect(opened.isEmpty)
        #expect(selection == .page(page))
    }

    @Test("routeOpen suppresses when the tapped page already fills the main pane")
    func routeOpenSuppressedNoOps() {
        let collection = makeCollection(openIn: .compact)
        let page = makePage()
        var selection = SidebarSelection.page(page)
        var opened: [PageRef] = []

        let routed = PageOpenRouter.routeOpen(
            page, pageCollection: collection, collection: nil, set: nil, selection: &selection
        ) { opened.append($0) }

        #expect(routed == .suppressed)
        #expect(opened.isEmpty)
        #expect(selection == .page(page))
    }
}
