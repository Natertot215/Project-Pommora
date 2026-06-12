import SwiftUI

/// **Layout spike** — a throwaway-but-real prototype of the custom table's
/// scroll architecture, staged here so the scroll feel can be hands-tested
/// before the production table (Task 9) is built on top of it.
///
/// **The architecture (research-validated):** a single
/// `ScrollView([.vertical, .horizontal])` + `pinnedViews` combo is an
/// Apple-acknowledged BROKEN combination. Instead this uses **axis-split
/// nested ScrollViews**:
///
/// - **Outer** `ScrollView(.horizontal)` owns horizontal panning.
/// - A **width-framed pane** (sum of fixed column widths) is the horizontal
///   content; it never compresses, so columns stay aligned.
/// - **Inner** `ScrollView(.vertical)` owns vertical scrolling of the body.
/// - The **column header** is mounted via `.safeAreaInset(edge: .top)` on the
///   *inner* vertical scroll view, so it stays pinned vertically while panning
///   horizontally with the body in perfect column alignment.
///
/// **No `pinnedViews` anywhere** — the group disclosure rows scroll naturally
/// with the content (round-2 direction).
struct TableLayoutSpike: View {

    // MARK: Fixed column model

    /// 8 fixed-width columns. Titles + widths are dummy spike data.
    private static let columns: [Column] = [
        Column(title: "Title", width: 220),
        Column(title: "Status", width: 120),
        Column(title: "Date", width: 140),
        Column(title: "Owner", width: 160),
        Column(title: "Priority", width: 110),
        Column(title: "Tags", width: 180),
        Column(title: "Progress", width: 120),
        Column(title: "Notes", width: 240),
    ]

    /// Sum of all fixed column widths — the width the horizontal pane is framed
    /// to so columns never compress and stay aligned with the header.
    private static let totalWidth: CGFloat = columns.reduce(0) { $0 + $1.width }

    private static let rowHeight: CGFloat = 26

    /// 3 fake disclosure-row groups, each holding 200 dummy data rows.
    private static let groups: [Group] = (0..<3).map { g in
        Group(
            id: g,
            label: "Group \(g + 1)",
            rows: (0..<200).map { r in
                Row(
                    id: "\(g)-\(r)",
                    cells: columns.enumerated().map { idx, col in
                        "\(col.title) \(r + 1).\(idx + 1)"
                    }
                )
            }
        )
    }

    // MARK: Body

    var body: some View {
        // Outer: owns horizontal panning.
        ScrollView(.horizontal) {
            // Width-framed pane — columns never compress, header + body align.
            VStack(spacing: 0) {
                // Inner: owns vertical scrolling of the body.
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Self.groups) { group in
                            GroupSection(group: group, columns: Self.columns, rowHeight: Self.rowHeight)
                        }
                    }
                }
                // Column header pinned vertically, panning horizontally with body.
                .safeAreaInset(edge: .top, spacing: 0) {
                    HeaderRow(columns: Self.columns, rowHeight: Self.rowHeight)
                }
            }
            .frame(width: Self.totalWidth)
        }
    }
}

// MARK: - Group section (fake disclosure)

/// A statically-expandable disclosure group: a native-Table-styled header row
/// (chevron + label) followed by its data rows. The `@State` toggle is a
/// convenience — collapse need not be production-correct in the spike.
private struct GroupSection: View {
    let group: TableLayoutSpike.Group
    let columns: [TableLayoutSpike.Column]
    let rowHeight: CGFloat

    @State private var isExpanded = true

    var body: some View {
        // Disclosure header row — looks like a native Table group row.
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: PUI.Spacing.sm) {
                Image(systemName: "chevron.right")
                    .font(PUI.Icon.chevron)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(group.label)
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PUI.Spacing.md)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.quaternary)

        if isExpanded {
            ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                DataRow(row: row, columns: columns, rowHeight: rowHeight, visualIndex: index)
            }
        }
    }
}

// MARK: - Rows

/// The pinned column-header row — same 8 fixed-width cells as the body so it
/// pans horizontally in perfect column alignment.
private struct HeaderRow: View {
    let columns: [TableLayoutSpike.Column]
    let rowHeight: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns) { column in
                Text(column.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: column.width, height: rowHeight, alignment: .leading)
                    .padding(.horizontal, PUI.Spacing.md)
            }
        }
        .frame(height: rowHeight)
        .background(.bar)
    }
}

/// A single 26pt data row: an `HStack(spacing: 0)` of 8 fixed-width column
/// cells. Alternating fill uses the subtler quinary fill (`PUI.Fill.field`),
/// striped by visual row index.
private struct DataRow: View {
    let row: TableLayoutSpike.Row
    let columns: [TableLayoutSpike.Column]
    let rowHeight: CGFloat
    let visualIndex: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                Text(row.cells[index])
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: column.width, height: rowHeight, alignment: .leading)
                    .padding(.horizontal, PUI.Spacing.md)
            }
        }
        .frame(height: rowHeight)
        .background(visualIndex.isMultiple(of: 2) ? AnyShapeStyle(.clear) : PUI.Fill.field)
    }
}

// MARK: - Dummy data model

extension TableLayoutSpike {
    struct Column: Identifiable {
        let title: String
        let width: CGFloat
        var id: String { title }
    }

    struct Row: Identifiable {
        let id: String
        let cells: [String]
    }

    struct Group: Identifiable {
        let id: Int
        let label: String
        let rows: [Row]
    }
}
