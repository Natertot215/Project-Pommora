import AppKit
import SwiftUI

/// SwiftUI content for one cell of the wrapped `NSOutlineView` table, mounted in
/// an `NSHostingView` inside a native `NSTableColumn`. Switches on the column
/// kind to render the title, modified, or property/tier cell — the same per-kind
/// rendering the table has always used, now hosted in native columns.
///
/// Selection and double-click-to-open are owned by the outline view (native), so
/// this content carries NO tap gestures — only the per-row context menu and the
/// property editor's own popover. Per-cell rendering is isolated into value-typed
/// sub-views (GRDB `String` overload hygiene; `first(where:)`, never `contains`).
struct ViewTableCellContent: View {
    let item: ViewItem
    let column: ResolvedColumn
    let schema: [PropertyDefinition]
    let index: PommoraIndex?
    let relationResolver: (String) -> (icon: String, title: String)?
    let commit: (PropertyDefinition, PropertyValue?) -> Void
    let menu: (ViewItem) -> AnyView

    var body: some View {
        cell
            .padding(.horizontal, PUI.Spacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var cell: some View {
        switch column.kind {
        case .title:
            Label {
                Text(item.page.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                CellIconGlyph(icon: item.page.frontmatter.icon)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu { menu(item) }
        case .modified:
            Text(
                (item.page.frontmatter.modifiedAt ?? item.page.frontmatter.createdAt)
                    .formatted(date: .abbreviated, time: .shortened)
            )
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .tier, .property:
            CellPropertyHost(
                item: item,
                definition: definition,
                index: index,
                relationResolver: relationResolver,
                commit: commit)
        }
    }

    /// Column → schema definition via `first(where:)`, never `contains`. Tier
    /// columns resolve through the same merged schema.
    private var definition: PropertyDefinition? {
        schema.first(where: { $0.id == column.id })
    }
}

// MARK: - Group header cell

/// The disclosure-row content for a structural / property group, hosted in the
/// outline column. The disclosure triangle + indentation are drawn by the outline
/// view itself; this supplies the folder icon + slightly-bold title (native
/// disclosure-row language) plus the group's context menu.
struct ViewGroupHeaderCell: View {
    let group: ResolvedGroup
    let menu: (ResolvedGroup) -> AnyView

    var body: some View {
        Label {
            Text(group.title)
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, PUI.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu { menu(group) }
    }

    /// SF Symbol per group kind — folders for structural containers, a tag for a
    /// property bucket, a tray for the ungrouped band.
    private var icon: String {
        switch group.kind {
        case .structuralCollection, .structuralSet: return "folder"
        case .propertyBucket: return "tag"
        case .ungrouped: return "tray"
        }
    }
}

// MARK: - Page icon glyph

/// Renders a page's frontmatter icon, tolerating BOTH SF Symbol names and
/// arbitrary glyph strings (emoji / custom text). `Image(systemName:)` draws a
/// broken placeholder for a non-symbol value, so a string that isn't a valid SF
/// Symbol falls back to a plain `Text` glyph; a nil icon uses `doc.text`.
private struct CellIconGlyph: View {
    let icon: String?

    var body: some View {
        switch resolved {
        case .symbol(let name): Image(systemName: name)
        case .glyph(let text): Text(text)
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

// MARK: - Property / tier cell host

/// Hosts `PropertyCellEditor` (editor-on-demand, popover commit-on-dismiss) as an
/// isolated value-typed sub-view so the relation-vs-scalar selection stays out of
/// the parent `@ViewBuilder`.
private struct CellPropertyHost: View {
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
                index: index)
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
