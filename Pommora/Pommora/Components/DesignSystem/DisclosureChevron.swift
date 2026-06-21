import SwiftUI

/// The shared disclosure chevron: a `chevron.right` that rotates to point down
/// when expanded, tuned to read identically to macOS's native `DisclosureGroup`
/// indicator (the sidebar's chevron is the ground-truth reference).
///
/// Pommora draws its own chevron only where a native one is unavailable — the
/// detail table's `NSOutlineView` group headers (which natively offer a triangle,
/// not a chevron) and the grouping pane's Group-By picker. The sidebar keeps the
/// genuine native chevron, so this stays matched against it.
struct DisclosureChevron: View {
    let isExpanded: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(PUI.Icon.chevron)
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}
