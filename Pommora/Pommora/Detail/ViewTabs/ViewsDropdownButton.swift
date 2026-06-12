import SwiftUI

/// Toolbar button that opens the Views dropdown popover (switch / manage the
/// container's saved views).
///
/// Mirrors `ViewSettingsButton`: statically positioned at ContentView level
/// with a reactive `scope` param, a `.popover(arrowEdge: .bottom)`, and the
/// FULL Nexus environment injected at the popover boundary (quirk #15 — macOS
/// popovers present detached from the ancestor env chain).
///
/// Two display modes, toggled via a right-click context menu and persisted
/// through `NexusState.viewsButtonStyle` (`OrderPersister.setViewsButtonStyle`):
///   - `.icon` — compact icon-only chip (65×36pt).
///   - `.title` — liquid-glass button showing the active view's icon + title.
struct ViewsDropdownButton: View {
    let scope: ViewSettingsScope

    /// Threaded in explicitly (the toolbar lives outside ContentView's
    /// `.environment(...)` chain — reading via `@Environment` here SIGTRAPs at
    /// toolbar render). The popover content gets the full env via
    /// `injectNexusEnvironment`.
    let pageTypeManager: PageTypeManager
    let activeViewStore: ActiveViewStore

    @State private var isPresented = false
    @State private var style: ViewsButtonStyle = .icon

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label
        }
        .buttonStyle(.plain)
        .disabled(containerID == nil)
        .help("Views")
        .onAppear { style = ViewsButtonStyle.loaded(from: AppGlobals.current) }
        .contextMenu {
            switch style {
            case .icon:
                Button("Show View Title") { setStyle(.title) }
            case .title:
                Button("Hide View Title") { setStyle(.icon) }
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popoverContent
        }
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .icon:
            Image(systemName: "rectangle.grid.1x2")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 65, height: 36)
                .contentShape(Rectangle())
        case .title:
            HStack(spacing: 6) {
                Image(systemName: activeView?.icon ?? "rectangle.grid.1x2")
                    .font(.system(size: 12, weight: .medium))
                Text(activeView?.name ?? "Views")
                    .font(.callout)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .contentShape(Rectangle())
            .glassEffect()
        }
    }

    @ViewBuilder
    private var popoverContent: some View {
        if let env = AppGlobals.current, let cid = containerID {
            ViewsPanel(containerID: cid, onDismiss: { isPresented = false })
                .injectNexusEnvironment(env)
        } else {
            Text("No view-bearing container selected.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding()
        }
    }

    // MARK: - Resolution

    private var containerID: String? {
        switch scope {
        case .pageType(let t): return t.id
        case .pageCollection(let c): return c.id
        default: return nil
        }
    }

    private var activeView: SavedView? {
        guard let cid = containerID else { return nil }
        let views: [SavedView]
        if let t = pageTypeManager.types.first(where: { $0.id == cid }) {
            views = t.views
        } else if let c = pageTypeManager.pageCollectionsByType.values
            .flatMap({ $0 }).first(where: { $0.id == cid })
        {
            views = c.views
        } else {
            return nil
        }
        let stored = activeViewStore.activeViewID(for: cid)
        return views.first(where: { $0.id == stored }) ?? views.first
    }

    private func setStyle(_ newStyle: ViewsButtonStyle) {
        style = newStyle
        if let nexus = AppGlobals.current?.nexusManager.currentNexus {
            try? OrderPersister.setViewsButtonStyle(newStyle.rawValue, in: nexus)
        }
    }
}

/// Display mode for the toolbar Views button, persisted as `NexusState`'s
/// `views_button_style` string. Modeled as an enum + switch (HARD RULE).
enum ViewsButtonStyle: String {
    case icon
    case title

    /// Reads the persisted style off the open Nexus's `state.json`, defaulting
    /// to `.icon` when absent or unreadable.
    @MainActor
    static func loaded(from env: NexusEnvironment?) -> ViewsButtonStyle {
        guard let nexus = env?.nexusManager.currentNexus else { return .icon }
        let url = NexusPaths.nexusStateURL(in: nexus)
        let state = (try? AtomicJSON.decode(NexusState.self, from: url)) ?? NexusState()
        return state.viewsButtonStyle.flatMap(ViewsButtonStyle.init(rawValue:)) ?? .icon
    }
}
