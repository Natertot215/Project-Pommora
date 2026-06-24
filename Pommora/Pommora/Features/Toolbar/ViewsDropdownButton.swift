import SwiftUI

/// Fixed-width, icon-only button that opens the Views dropdown popover (switch /
/// manage the container's saved views).
///
/// Hosted as a toolbar item — the leading pill of the trailing primary-action
/// cluster (see `ContentView.viewsButtonCapsule`). The popover content gets the
/// full Nexus environment injected at its boundary (`AppGlobals.current`), since
/// the toolbar lives outside ContentView's injected env chain.
struct ViewsDropdownButton: View {
    let scope: ViewSettingsScope
    /// Threaded explicitly — the toolbar lives outside ContentView's environment
    /// chain, so reading these via @Environment SIGTRAPs at toolbar render. Used
    /// to reflect the active view's icon on the button.
    let collectionManager: PageCollectionManager
    let activeViewStore: ActiveViewStore

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: buttonIcon)
                .toolbarGlyph(width: PUI.Icon.toolbarViewsFrame)
        }
        .help("Views")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popoverContent
        }
    }

    @ViewBuilder
    private var popoverContent: some View {
        if let env = AppGlobals.current, let cid = containerID {
            // No background modifier — a toolbar-anchored popover gets Apple's
            // Liquid-Glass chrome automatically (matches the settings popover).
            ViewsPanel(containerID: cid, onDismiss: { isPresented = false })
                .injectNexusEnvironment(env)
        } else {
            Text("No view-bearing container selected.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding()
        }
    }

    /// The active view's icon when one is set; otherwise the default Views glyph.
    private var buttonIcon: String {
        activeView?.icon ?? "rectangle.3.group"
    }

    private var activeView: SavedView? {
        guard let cid = containerID else { return nil }
        return activeViewStore.resolvedActiveView(in: cid, manager: collectionManager)
    }

    private var containerID: String? {
        switch scope {
        case .pageCollection(let t): return t.id
        case .pageSetCollection(let c): return c.id
        default: return nil
        }
    }
}
