import SwiftUI

/// Shared header used at the top of every View Settings sub-pane
/// (PropertiesListPane / PropertyVisibilityPane / PropertyTypePickerPane /
/// EditPropertyPane / EditOptionPane).
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
/// All dimensions route through `PUI.Pane.Header` + `PUI.Icon.backChevron` +
/// `PUI.Typography.paneTitle` for consistency across panes.
///
/// **Usage** (every pane top):
/// ```swift
/// var body: some View {
///     VStack(spacing: 0) {
///         PaneHeader(path: $path, title: "Edit Properties")
///         // ... pane content
///     }
///     .frame(width: PUI.Pane.width, height: PUI.Pane.height)
///     .navigationBarBackButtonHidden(true)
/// }
/// ```
struct PaneHeader: View {
    @Binding var path: [ViewSettingsRoute]
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: PUI.Pane.Header.interSpacing) {
                Button {
                    if !path.isEmpty { path.removeLast() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(PUI.Icon.backChevron)
                        .foregroundStyle(.secondary)
                        .frame(width: PUI.Pane.Header.chevronFrame, height: PUI.Pane.Header.chevronFrame)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back")

                Text(title)
                    .font(PUI.Typography.paneTitle)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, PUI.Pane.Header.paddingHorizontal)
            .padding(.top, PUI.Pane.Header.paddingTop)
            .padding(.bottom, PUI.Pane.Header.paddingBottom)

            Divider()
        }
    }
}
