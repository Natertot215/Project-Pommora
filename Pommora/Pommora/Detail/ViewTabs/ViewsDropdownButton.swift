import SwiftUI

/// Fixed-width, icon-only button that opens the Views dropdown popover (switch /
/// manage the container's saved views).
///
/// Rendered as an in-content overlay control (see `ContentView.detailViewControls`),
/// NOT an `NSToolbar` item — so it carries no system "Icon & Text" toggle. The
/// popover content gets the full Nexus environment injected at its boundary
/// (`AppGlobals.current`), since the overlay sits outside the injected env chain.
struct ViewsDropdownButton: View {
    let scope: ViewSettingsScope

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "rectangle.grid.2x2")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 64, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private var containerID: String? {
        switch scope {
        case .pageType(let t): return t.id
        case .pageCollection(let c): return c.id
        default: return nil
        }
    }
}
