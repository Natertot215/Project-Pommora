import SwiftUI

/// A native-table-styled disclosure GROUP header row for the custom table:
/// chevron + grouping label + item count. Carries the migrated container
/// context menu (Collection rows in vault scope, Set rows in collection scope).
///
/// These rows SCROLL with the content (no `pinnedViews`) — round-2 direction
/// mirrored from `TableLayoutSpike`. The headerless ungrouped band renders no
/// `TableGroupRow` at all (the renderer emits its item rows directly).
struct TableGroupRow: View {
    let group: ResolvedGroup
    /// Visual indentation depth — 0 for a Collection group, 1 for a Set nested
    /// under its Collection (vault scope).
    let depth: Int
    let isExpanded: Bool
    let totalWidth: CGFloat
    let onToggle: () -> Void
    let menu: (ResolvedGroup) -> AnyView

    private static let rowHeight: CGFloat = 26

    /// Total item count under this group (own items + every descendant's).
    private var count: Int { group.flattenedItems.count }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: PUI.Spacing.sm) {
                Image(systemName: "chevron.right")
                    .font(PUI.Icon.chevron)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(group.title)
                    .font(.callout.weight(.semibold))
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * PUI.Spacing.lg)
            .padding(.horizontal, PUI.Spacing.md)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: totalWidth, alignment: .leading)
        .background(.quaternary)
        .contextMenu { menu(group) }
    }
}
