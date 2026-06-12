import SwiftUI

/// A native-table-styled disclosure GROUP header row for the custom table —
/// laid out exactly like a native `DisclosureTableRow`: the disclosure triangle
/// + folder/group icon + group name + item count sit INSIDE the leading Title
/// column's width (indented by depth), and the row continues blank across the
/// remaining columns. Same height as a data row, fully TRANSPARENT so the
/// renderer's continuous alternating stripe shows through — an inline row, NOT a
/// full-width band.
///
/// These rows SCROLL with the content (no `pinnedViews`). The headerless
/// ungrouped band renders no `TableGroupRow` at all (the renderer emits its
/// item rows directly).
struct TableGroupRow: View {
    let group: ResolvedGroup
    /// Visual indentation depth — 0 for a Collection group, 1 for a Set nested
    /// under its Collection (vault scope).
    let depth: Int
    let isExpanded: Bool
    /// Highlighted while a row drag hovers this group as a move / rewrite target.
    /// Driven by `RowDragCoordinator.highlightedGroupID`.
    var isDropTarget: Bool = false
    /// The leading Title column's live width — the disclosure label is confined
    /// to this width (left-aligned, depth-indented) so it lines up under the
    /// "Name" header exactly like a native `DisclosureTableRow`.
    let titleWidth: CGFloat
    let onToggle: () -> Void
    let menu: (ResolvedGroup) -> AnyView

    /// Row height — matched to the data rows so the inline group row aligns with
    /// the renderer's continuous stripe bands.
    private static var rowHeight: CGFloat { TableRowView.rowHeight }

    /// Total item count under this group (own items + every descendant's).
    private var count: Int { group.flattenedItems.count }

    var body: some View {
        Button(action: onToggle) {
            // The disclosure label occupies ONLY the Title column's width; the
            // remaining columns stay blank (the row frame extends past it).
            HStack(spacing: PUI.Spacing.xs) {
                Image(systemName: "chevron.right")
                    .font(PUI.Icon.chevron)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(group.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * PUI.Spacing.lg)
            .padding(.horizontal, PUI.Spacing.md)
            // Confine the disclosure label to the Title column's width, then let
            // the row frame extend full-width — the blank remainder trails right.
            .frame(width: titleWidth, alignment: .leading)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Inline native-outline disclosure row — transparent so the renderer's
        // continuous stripe shows through. Only the functional drop-target tint
        // paints a background. The row spans the full content width (the hit +
        // layout target) via `maxWidth: .infinity` on the label above.
        .background(isDropTarget ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear))
        .contextMenu { menu(group) }
    }
}
