import SwiftUI

/// View Settings popover content — chrome-only placeholder slice.
///
/// At v0.3.1.x this is an empty Liquid Glass shell at a fixed 300x360pt size,
/// to validate the chrome before pane content lands. In v0.3.1 this gets
/// replaced by a NavigationStack with real panes (Layout / Property Visibility
/// / Sort / Filter / Group / Edit Properties).
///
/// Liquid Glass background is auto-applied by the toolbar-anchored popover
/// (WWDC25 #323). Do NOT apply .background(.regularMaterial) or
/// .glassEffect() — Apple drives the chrome.
///
/// Dismissal: outside-click and ESC are SwiftUI's defaults for popovers; no
/// in-popover close affordance needed at this slice.
struct ViewSettingsPopover: View {
    /// Which surface the popover currently reflects. Unused at this slice;
    /// kept so the static-button / adaptive-content wiring ships intact and
    /// follow-up slices only have to swap the body.
    let scope: ViewSettingsScope

    var body: some View {
        Color.clear
            .frame(width: 300, height: 360)
    }
}

#if DEBUG
    #Preview("Empty shell") {
        ViewSettingsPopover(
            scope: .pageType(
                PageType(
                    id: "01HPT", title: "Notes", icon: nil,
                    properties: [], views: [], modifiedAt: Date()
                )
            )
        )
    }
#endif
