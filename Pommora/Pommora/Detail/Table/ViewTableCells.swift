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
                PageIconGlyph(icon: item.page.frontmatter.icon)
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

/// The reactive expansion state backing a group header's `DisclosureChevron`.
/// Owned by the table coordinator (one per group id, reused across reloads) and
/// flipped in lockstep with the native fold so the chevron animates rather than
/// snapping. A reference type so the value-typed `ViewGroupHeaderCell` observes it
/// live without the cell being re-hosted on every toggle.
@MainActor @Observable
final class GroupDisclosureState {
    var isExpanded: Bool
    init(isExpanded: Bool) { self.isExpanded = isExpanded }
}

/// The disclosure-row content for a structural / property group, hosted in the
/// outline column. The native triangle is suppressed (`ChevronlessOutlineView`);
/// this draws the shared `DisclosureChevron` in its place — matched to the
/// sidebar's native chevron — plus the folder icon + slightly-bold title and the
/// group's context menu.
struct ViewGroupHeaderCell: View {
    let group: ResolvedGroup
    let disclosure: GroupDisclosureState
    let menu: (ResolvedGroup) -> AnyView

    var body: some View {
        HStack(spacing: PUI.Spacing.xs) {
            // Fixed gutter so the title doesn't shift as the chevron rotates.
            DisclosureChevron(isExpanded: disclosure.isExpanded)
                .frame(width: 12)
            Label {
                Text(group.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
            }
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
                value: item.page.frontmatter.cellValue(for: definition),
                relationResolver: relationResolver,
                commit: { newValue in commit(definition, newValue) },
                index: index)
        } else {
            Color.clear
        }
    }
}
