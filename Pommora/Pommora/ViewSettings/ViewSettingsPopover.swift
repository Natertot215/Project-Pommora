import SwiftUI

/// View Settings popover content.
///
/// Storage scopes (PageType / PageCollection)
/// render `StorageMenuRoot` — a Notion-style root menu with active Edit
/// Properties + Layout + Group + Filter + Sort rows plus a muted Templates
/// row. Non-storage scopes
/// (Areas / Topics / Projects / Pages / Calendar / none) keep the empty
/// 300x360pt shell from the v0.3.0.5 chrome slice; their View Settings
/// surfaces ship in later versions.
///
/// NavigationStack drives the per-route push: root menu rows append routes
/// to `path`; `.navigationDestination(for:)` resolves each route to a
/// pushed pane (PropertiesListPane / PropertyTypePickerPane /
/// EditPropertyPane / LayoutPane). Option editing is inline via
/// `OptionEditPopover`, not a route.
///
/// Liquid Glass background is auto-applied by the toolbar-anchored popover
/// (WWDC25 #323). Do NOT apply .background(.regularMaterial) or
/// .glassEffect() — Apple drives the chrome.
///
/// Dismissal: outside-click and ESC are SwiftUI's defaults for popovers; no
/// in-popover close affordance needed.
struct ViewSettingsPopover: View {
    let scope: ViewSettingsScope

    @State private var path: [ViewSettingsRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            rootContent
                .navigationDestination(for: ViewSettingsRoute.self) { route in
                    destination(for: route)
                }
        }
        // Width-locked; `fixedSize` makes the NavigationStack hug the active
        // pane's definite height (each pane self-sizes between
        // PUI.Pane.minHeight and .maxHeight via ViewSettingsPane). The system
        // NSPopover owns the resize (it snaps content-size changes — the
        // accepted behavior; SwiftUI can't animate the glass window's height).
        .frame(width: PUI.Pane.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var rootContent: some View {
        switch scope {
        case .pageType, .pageCollection:
            StorageMenuRoot(scope: scope, path: $path)
        default:
            // Non-storage scopes: empty 300x360 shell retained from chrome slice.
            // Per-scope panes for those surfaces ship in later versions. Sized
            // explicitly so the content-hugging NavigationStack has a definite
            // height here (Color.clear has no intrinsic size of its own).
            Color.clear
                .frame(width: PUI.Pane.width, height: PUI.Pane.minHeight)
        }
    }

    /// Resolves each pushed route to its pane.
    @ViewBuilder
    private func destination(for route: ViewSettingsRoute) -> some View {
        switch route {
        case .editProperties:
            PropertiesListPane(scope: scope, path: $path)
        case .propertyTypePicker:
            PropertyTypePickerPane(scope: scope, path: $path)
        case .editProperty(let id):
            EditPropertyPane(scope: scope, propertyID: id, path: $path)
        case .layout:
            LayoutPane(scope: scope, path: $path)
        case .sort:
            SortPane(scope: scope, path: $path)
        case .filter:
            FilterPane(scope: scope, path: $path)
        case .group:
            GroupPane(scope: scope, path: $path)
        }
    }
}

#if DEBUG
#Preview("Popover — PageType scope") {
    ViewSettingsPopover(
        scope: .pageType(
            PageType(
                id: "01HPT", title: "Notes", icon: "note.text",
                properties: [], views: [], modifiedAt: Date()
            )
        )
    )
}

#Preview("Popover — none scope (empty shell)") {
    ViewSettingsPopover(scope: .none)
}
#endif
