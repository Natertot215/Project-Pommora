import SwiftUI

/// The custom table's pinned column-header row. Mounted via `.safeAreaInset`
/// on the inner vertical scroll view (see `CustomTableView`) so it stays fixed
/// vertically while panning horizontally with the body in column alignment.
///
/// Each header cell = the `ResolvedColumn`'s icon + title, fixed to the live
/// column width (`ColumnLayout.widths`) so it tracks future resize (Task 10).
struct TableHeaderRow: View {
    let columns: [ResolvedColumn]
    let widths: [Double]
    let rowHeight: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                HeaderCell(column: column, width: width(at: index), rowHeight: rowHeight)
            }
        }
        .frame(height: rowHeight)
        .background(.bar)
    }

    private func width(at index: Int) -> CGFloat {
        guard widths.indices.contains(index) else { return CGFloat(column(at: index).width) }
        return CGFloat(widths[index])
    }

    private func column(at index: Int) -> ResolvedColumn { columns[index] }
}

/// One header cell — isolated as a plain value-typed sub-view (quirk #12) so the
/// per-column rendering stays out of the parent `@ViewBuilder`.
private struct HeaderCell: View {
    let column: ResolvedColumn
    let width: CGFloat
    let rowHeight: CGFloat

    var body: some View {
        HStack(spacing: PUI.Spacing.xs) {
            Image(systemName: column.iconName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(column.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(width: width, height: rowHeight, alignment: .leading)
        .padding(.horizontal, PUI.Spacing.md)
    }
}
