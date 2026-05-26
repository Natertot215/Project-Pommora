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

    /// Env values consumed here at the button's level (where ContentView's
    /// `.environment(...)` chain DOES propagate) and re-injected into the
    /// popover content closure. Without this, macOS popovers present their
    /// content in a detached context that doesn't inherit the ancestor
    /// environment chain — every `@Environment(PageTypeManager.self)` /
    /// `@Environment(ItemTypeManager.self)` inside the popover hierarchy
    /// (PropertiesListPane / EditPropertyPane / EditOptionPane /
    /// PropertyVisibilityPane / PropertyTypePickerPane) asserts at first
    /// render with "No Observable object of type X found." A popover-level
    /// variant of quirk #16.
    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(ItemTypeManager.self) private var itemTypeManager

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
        }
    }
}

#if DEBUG
    #Preview("Button (pageType scope)") {
        ViewSettingsButton(
            scope: .pageType(
                PageType(
                    id: "01HPT", title: "Notes", icon: nil,
                    properties: [], views: [], modifiedAt: Date()
                )
            )
        )
        .padding()
    }
#endif
