import SwiftUI

/// Toolbar button that opens the View Settings popover.
///
/// Statically positioned at ContentView level (NOT per-detail-view) inside
/// the primary-action cluster's trio pill, sharing one Liquid Glass capsule
/// with Navigation + Inspector toggle.
///
/// The `scope` parameter is reactive: when ContentView's selection changes,
/// ContentView recomputes the scope and SwiftUI re-passes it here, causing
/// the open popover (if any) to re-render its content against the new scope.
/// The button itself never moves.
///
/// Width-22 icon (matching the trio buttons); height is system-owned via the
/// default toolbar button style, so the three buttons read as a uniform pill.
struct ViewSettingsButton: View {
    let scope: ViewSettingsScope

    /// Managers passed in as explicit params (NOT @Environment) because the
    /// toolbar where this button lives is OUTSIDE ContentView's
    /// `.detail { ... }` closure's `.environment(...)` chain. Reading these
    /// via `@Environment(PageTypeManager.self)` here asserts at toolbar
    /// render (app launch crash).
    ///
    /// macOS popovers present their content in a detached context that doesn't
    /// inherit the button's ancestor env chain, so explicit injection at the
    /// popover boundary is required for every popover-hosted view that declares
    /// `@Environment(X.self)`. We inject the FULL Nexus environment via
    /// `.injectNexusEnvironment(_:)` (sourced from `AppGlobals.current`, the
    /// live env) rather than hand-injecting a partial subset — a missing manager
    /// SIGTRAPs a `.task`-bearing view (macOS popover env-chain detachment). The full inject is a
    /// superset of every pane's needs, so it's safe. These params are still
    /// threaded in because the toolbar lives OUTSIDE ContentView's
    /// `.environment(...)` chain; they remain available for any future
    /// button-level use.
    let pageTypeManager: PageTypeManager
    let tierConfigManager: TierConfigManager
    /// Threaded in pre-emptively: the `.page` scope's settings pane (not built
    /// yet — currently renders empty) will read this to edit a page's icon /
    /// title. Injected onto the popover env now so that future pane needs no
    /// plumbing change when it lands.
    let pageContentManager: PageContentManager

    @State private var isPresented: Bool = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .toolbarGlyph(width: PUI.Icon.toolbarActionFrame)
        }
        .help("View Settings")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            popoverContent
        }
    }

    /// Popover content with the FULL Nexus environment injected.
    /// `AppGlobals.current` is non-nil whenever a Nexus is open, which is always
    /// true when the popover is reachable; if it's somehow absent we fall back to
    /// the bare popover (no panes that need managers can be reached anyway).
    @ViewBuilder
    private var popoverContent: some View {
        if let env = AppGlobals.current {
            ViewSettingsPopover(scope: scope)
                .injectNexusEnvironment(env)
        } else {
            ViewSettingsPopover(scope: scope)
        }
    }
}

// Preview removed at v0.3.1 — the new init signature requires a real
// PageTypeManager instance which needs a Nexus to construct. Use
// PommoraUIX (Cmd+Shift+D) for the live debug surface.
