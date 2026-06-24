import SwiftUI

// MARK: - FooterCrumb

/// A single breadcrumb segment. `action` nil = current/non-navigable segment.
/// `isGhost` tints the segment tertiary — used for the last-visited page trail
/// shown in a collection view after navigating back from a page.
struct FooterCrumb {
    let title: String
    var isGhost: Bool = false
    var action: (() -> Void)?

    init(title: String, isGhost: Bool = false, action: (() -> Void)? = nil) {
        self.title = title
        self.isGhost = isGhost
        self.action = action
    }
}

// MARK: - FooterBreadcrumbView

/// Renders `[Collection] › [Collection] › [Page]` breadcrumb segments inline.
/// Tappable segments call their `action`; the current/last segment has no action.
/// Ghost segments (trail) render tertiary.
struct FooterBreadcrumbView: View {
    let crumbs: [FooterCrumb]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(crumbs.enumerated()), id: \.offset) { idx, crumb in
                if idx > 0 {
                    separator
                }
                crumbView(crumb)
            }
        }
    }

    private var separator: some View {
        Text(" › ")
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func crumbView(_ crumb: FooterCrumb) -> some View {
        let style: HierarchicalShapeStyle = crumb.isGhost ? .tertiary : .secondary
        if let action = crumb.action {
            Button(action: action) {
                Text(crumb.title)
                    .foregroundStyle(style)
            }
            .buttonStyle(.plain)
        } else {
            Text(crumb.title)
                .foregroundStyle(style)
        }
    }
}

// MARK: - DetailFooterBar

/// Unified footer chrome used by all detail views and the page editor.
/// Breadcrumb segments on the left; caller-supplied trailing content on the right.
/// Applies the shared subheadline / secondary treatment and consistent padding.
struct DetailFooterBar<Trailing: View>: View {
    let crumbs: [FooterCrumb]
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            FooterBreadcrumbView(crumbs: crumbs)
                .foregroundStyle(.secondary)
            Spacer(minLength: PUI.Spacing.xl)
            trailing()
        }
        .font(.subheadline)
        .padding(.horizontal, PUI.Spacing.xl)
        .padding(.vertical, PUI.Spacing.sm)
        .frame(maxWidth: .infinity)
    }
}
