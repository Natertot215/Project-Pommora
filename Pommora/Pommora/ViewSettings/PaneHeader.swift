import SwiftUI

/// Shared header used at the top of every View Settings sub-pane
/// (PropertiesListPane / PropertyVisibilityPane / PropertyTypePickerPane /
/// EditPropertyPane).
///
/// **Why this exists:** on macOS, `.navigationTitle(_:)` inside a
/// NavigationStack pushed via popover renders a dark NavigationStack toolbar
/// band that cuts through the popover top (visible as the chopped
/// "perty Visibility" / "+ New Property" titles in v0.3.1.0 visual smoke).
/// `.toolbar(.hidden)` on the pushed pane *suppresses the entire pane*, not
/// just the chrome. The fix is to render the header in-content (chevron +
/// title sitting on top of the popover's own Liquid Glass backdrop) and not
/// rely on NavigationStack's title chrome at all.
///
/// **Back-label convention (2026-05-27):** the header is a single back
/// affordance — a chevron + a small label naming the *previous* pane (the one
/// tapping back returns to), iOS-style. The current pane's identity comes from
/// its own content (e.g. EditPropertyPane's inline icon + name field), not a
/// duplicate title here. The label is derived from the route stack; when this
/// is the first pushed pane, it falls back to `rootLabel` (the root menu).
///
/// `showsDivider: false` drops the trailing divider for panes that render
/// their own (e.g. EditPropertyPane's icon/title field sits between the back
/// row and the first divider).
///
/// **Usage** (every pane top):
/// ```swift
/// VStack(spacing: 0) {
///     PaneHeader(path: $path)          // "‹ <previous pane>"
///     // ... pane content
/// }
/// .frame(width: PUI.Pane.width, height: PUI.Pane.height)
/// .navigationBarBackButtonHidden(true)
/// ```
struct PaneHeader: View {
    @Binding var path: [ViewSettingsRoute]
    /// Label shown when this is the first pushed pane (back returns to the
    /// root menu). Defaults to the generic "Settings".
    var rootLabel: String = "Settings"
    var showsDivider: Bool = true

    /// Names the pane the back-chevron returns to: the route one below the
    /// top of the stack, or `rootLabel` when this is the first pushed pane.
    private var previousLabel: String {
        path.count >= 2 ? path[path.count - 2].paneTitle : rootLabel
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: PUI.Pane.Header.interSpacing) {
                Button {
                    if !path.isEmpty { path.removeLast() }
                } label: {
                    HStack(spacing: PUI.Spacing.xs) {
                        Image(systemName: "chevron.left")
                            .font(PUI.Icon.backChevron)
                        Text(previousLabel)
                            .font(PUI.Typography.row)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back to \(previousLabel)")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, PUI.Pane.Header.paddingHorizontal)
            .padding(.top, PUI.Pane.Header.paddingTop)
            .padding(.bottom, PUI.Pane.Header.paddingBottom)

            if showsDivider { PaneDivider() }
        }
    }
}
