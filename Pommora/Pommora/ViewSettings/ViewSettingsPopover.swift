import SwiftUI

/// View Settings popover content.
///
/// Storage scopes (PageType / PageCollection / ItemType / ItemCollection)
/// render `StorageMenuRoot` — a Notion-style root menu with active Edit
/// Properties + Property Visibility rows plus muted Layout / Sort / Filter /
/// Group rows pointing at upcoming v0.3.1.x patches. Non-storage scopes
/// (Spaces / Topics / Projects / Pages / Calendar / none) keep the empty
/// 300x360pt shell from the v0.3.0.5 chrome slice; their View Settings
/// surfaces ship in later versions.
///
/// NavigationStack drives the per-route push: root menu rows append routes
/// to `path`; `.navigationDestination(for:)` resolves each route to a
/// pushed pane (PropertiesListPane / PropertyTypePickerPane /
/// EditPropertyPane / PropertyVisibilityPane). Option editing is inline via
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
        .measuredPaneHeight()
    }

    @ViewBuilder
    private var rootContent: some View {
        switch scope {
        case .pageType, .pageCollection, .itemType, .itemCollection:
            StorageMenuRoot(scope: scope, path: $path)
        default:
            // Non-storage scopes: empty 300x360 shell retained from chrome slice.
            // Per-scope panes for those surfaces ship in later versions.
            Color.clear
        }
    }

    /// Pushed-pane destinations. Task 7 shipped placeholders; Tasks 9-12
    /// replace each in-place with the real pane.
    @ViewBuilder
    private func destination(for route: ViewSettingsRoute) -> some View {
        switch route {
        case .editProperties:
            PropertiesListPane(scope: scope, path: $path)
        case .propertyTypePicker:
            PropertyTypePickerPane(scope: scope, path: $path)
        case .editProperty(let id):
            EditPropertyPane(scope: scope, mode: .edit(propertyID: id), path: $path)
        case .newRelation:
            EditPropertyPane(scope: scope, mode: .createRelation, path: $path)
        case .propertyVisibility:
            PropertyVisibilityPane(scope: scope, path: $path)
        }
    }

    private func placeholder(title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
            Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(title)
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
