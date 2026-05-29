import SwiftUI

/// Toolbar button that opens the View Settings popover.
///
/// Statically positioned at ContentView level (NOT per-detail-view) inside
/// the existing primary-action HStack so it shares the Liquid Glass capsule
/// with NavDropdown + Inspector toggle.
///
/// The `scope` parameter is reactive: when ContentView's selection changes,
/// ContentView recomputes the scope and SwiftUI re-passes it here, causing
/// the open popover (if any) to re-render its content against the new scope.
/// The button itself never moves.
///
/// Sizing matches the Inspector toggle next to it (same 22x16 icon frame)
/// so the three-button capsule reads as a uniform segmented group.
struct ViewSettingsButton: View {
    let scope: ViewSettingsScope

    /// Managers passed in as explicit params (NOT @Environment) because the
    /// toolbar where this button lives is OUTSIDE ContentView's
    /// `.detail { ... }` closure's `.environment(...)` chain. Reading these
    /// via `@Environment(PageTypeManager.self)` here asserts at toolbar
    /// render (app launch crash).
    ///
    /// We then re-inject them onto the popover content via `.environment(_:)`
    /// modifiers — macOS popovers present their content in a detached
    /// context that doesn't inherit the button's ancestor env chain either,
    /// so explicit injection at the popover boundary is required for
    /// every popover-hosted view that declares `@Environment(X.self)`
    /// (PropertiesListPane / PropertyTypePickerPane / EditPropertyPane /
    /// EditOptionPane / PropertyVisibilityPane). See quirk #16's two
    /// variants in Handoff.md.
    let pageTypeManager: PageTypeManager
    let itemTypeManager: ItemTypeManager
    let tierConfigManager: TierConfigManager

    @State private var isPresented: Bool = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 16)
                .contentShape(Rectangle())
        }
        .help("View Settings")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ViewSettingsPopover(scope: scope)
                .environment(pageTypeManager)
                .environment(itemTypeManager)
                .environment(tierConfigManager)
        }
    }
}

// Preview removed at v0.3.1 — the new init signature requires real
// PageTypeManager + ItemTypeManager instances which need a Nexus to
// construct. Use PommoraUIX (Cmd+Shift+D) for the live debug surface.
