import AppKit
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

    /// Whether this row sits in the current selection (drives the accent chrome).
    let isSelected: Bool
    /// Single-click select — the view resolves plain/⌘/⇧ from the live modifier
    /// mask and routes it through `TableSelectionModel`.
    let onSelect: (ViewItem) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { idx, column in
                cell(for: column)
                    .frame(width: width(at: idx), height: Self.rowHeight, alignment: .leading)
                    .padding(.horizontal, PUI.Spacing.md)
            }
        }
        .frame(height: Self.rowHeight)
        .background(stripeFill)
        // Row-local selection chrome (NOT the sidebar's listRowBackground
        // mechanism — this is a plain row): an accent-tinted fill mirroring the
        // native Table's focused-selection language.
        .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.clear))
        .contentShape(Rectangle())
        // simultaneousGesture so the title cell's double-click-to-open keeps
        // working; this single-tap drives selection without swallowing it.
        .simultaneousGesture(TapGesture().onEnded { onSelect(item) })
    }

    private var stripeFill: AnyShapeStyle {
        visualIndex.isMultiple(of: 2) ? AnyShapeStyle(.clear) : PUI.Fill.field
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
            PageIconGlyph(icon: item.page.frontmatter.icon)
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

// MARK: - Page icon glyph

/// Renders a page's frontmatter icon, tolerating BOTH SF Symbol names and
/// arbitrary glyph strings (emoji / custom text). `Image(systemName:)` draws a
/// broken placeholder for a non-symbol value, so a string that isn't a valid
/// SF Symbol falls back to a plain `Text` glyph. A nil icon uses the default
/// `doc.text` symbol. (No shared emoji-aware icon view exists in the codebase;
/// the page header + sidebar rows assume symbol-only icons.)
private struct PageIconGlyph: View {
    let icon: String?

    var body: some View {
        switch resolved {
        case .symbol(let name):
            Image(systemName: name)
        case .glyph(let text):
            Text(text)
        }
    }

    private enum Resolved {
        case symbol(String)
        case glyph(String)
    }

    private var resolved: Resolved {
        guard let icon, !icon.isEmpty else { return .symbol("doc.text") }
        if NSImage(systemSymbolName: icon, accessibilityDescription: nil) != nil {
            return .symbol(icon)
        }
        return .glyph(icon)
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
