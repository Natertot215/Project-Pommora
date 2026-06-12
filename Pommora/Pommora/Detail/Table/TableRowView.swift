import SwiftUI

/// One 26pt fixed-height data row for the custom table — an `HStack` of
/// fixed-width cells, one per `ResolvedColumn`. Alternating quinary fill
/// (`PUI.Fill.field`) is striped by VISUAL index (passed in by the renderer),
/// not `NSColor.alternatingContentBackgroundColors`.
///
/// Per-cell rendering is isolated into private value-typed sub-views (quirk #12
/// — GRDB `String`-overload pollution); column→definition resolution uses
/// `first(where:)`, never `contains`.
struct TableRowView: View {
    static let rowHeight: CGFloat = 26

    let item: ViewItem
    let columns: [ResolvedColumn]
    let widths: [Double]
    let schema: [PropertyDefinition]
    let visualIndex: Int

    /// SQLite index threaded for the inline `ContextPicker` (relation cells).
    let index: PommoraIndex?
    let relationResolver: (String) -> (icon: String, title: String)?
    let onDoubleTap: (ViewItem) -> Void
    let commit: (PropertyDefinition, PropertyValue?) -> Void
    let menu: (ViewItem) -> AnyView

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { idx, column in
                cell(for: column)
                    .frame(width: width(at: idx), height: Self.rowHeight, alignment: .leading)
                    .padding(.horizontal, PUI.Spacing.md)
            }
        }
        .frame(height: Self.rowHeight)
        .background(visualIndex.isMultiple(of: 2) ? AnyShapeStyle(.clear) : PUI.Fill.field)
    }

    @ViewBuilder
    private func cell(for column: ResolvedColumn) -> some View {
        switch column.kind {
        case .title:
            TitleCell(item: item, onDoubleTap: onDoubleTap, menu: menu)
        case .modified:
            ModifiedCell(date: item.page.frontmatter.modifiedAt ?? item.page.frontmatter.createdAt)
        case .tier, .property:
            PropertyCellHost(
                item: item,
                definition: definition(for: column),
                index: index,
                relationResolver: relationResolver,
                commit: commit
            )
        }
    }

    /// Column → schema definition via `first(where:)` (quirk #12: never
    /// `contains`). Tier columns resolve through the same merged schema.
    private func definition(for column: ResolvedColumn) -> PropertyDefinition? {
        schema.first(where: { $0.id == column.id })
    }

    private func width(at index: Int) -> CGFloat {
        guard widths.indices.contains(index) else { return CGFloat(columns[index].width) }
        return CGFloat(widths[index])
    }
}

// MARK: - Title cell

/// Title cell — the page icon + filename, carrying the double-click-to-open
/// gesture + the per-row context menu (Edit Title / Edit Icon / Pin / Delete).
private struct TitleCell: View {
    let item: ViewItem
    let onDoubleTap: (ViewItem) -> Void
    let menu: (ViewItem) -> AnyView

    var body: some View {
        Label {
            Text(item.page.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Image(systemName: item.page.frontmatter.icon ?? "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // simultaneousGesture (not onTapGesture) so double-click-to-open
        // coexists with future row selection (Task 11) instead of blocking it.
        .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleTap(item) })
        .contextMenu { menu(item) }
    }
}

// MARK: - Modified cell

private struct ModifiedCell: View {
    let date: Date

    var body: some View {
        Text(date.formatted(date: .abbreviated, time: .shortened))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Property / tier cell host

/// Hosts the existing `PropertyCellEditor` (editor-on-demand, popover
/// commit-on-dismiss) unchanged. Isolated as a value-typed sub-view (quirk #12)
/// so the relation-vs-scalar value selection stays out of the parent builder.
private struct PropertyCellHost: View {
    let item: ViewItem
    let definition: PropertyDefinition?
    let index: PommoraIndex?
    let relationResolver: (String) -> (icon: String, title: String)?
    let commit: (PropertyDefinition, PropertyValue?) -> Void

    var body: some View {
        if let definition {
            PropertyCellEditor(
                definition: definition,
                value: cellValue(definition),
                relationResolver: relationResolver,
                commit: { newValue in commit(definition, newValue) },
                index: index
            )
        } else {
            Color.clear
        }
    }

    private func cellValue(_ definition: PropertyDefinition) -> PropertyValue? {
        let fm = item.page.frontmatter
        if definition.type == .relation {
            return .relation(fm.relationIDs(forPropertyID: definition.id))
        }
        return fm.properties[definition.id]
    }
}
