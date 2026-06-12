import SwiftUI

/// The production custom table renderer — replaces the native display-only
/// `Table` in both detail views. Built on the Task-7 layout architecture
/// (`TableLayoutSpike`): a single `ScrollView(.horizontal)` owns horizontal
/// panning, a width-framed pane keeps columns from compressing, an inner
/// `ScrollView(.vertical)` owns body scrolling, and the column header is mounted
/// via `.safeAreaInset(edge:.top)` on the inner scroll so it pins vertically and
/// pans horizontally with the body. NO `pinnedViews` anywhere — group disclosure
/// rows scroll with the content.
///
/// Inputs are `ViewItem` + `ResolvedGroup` (the pipeline currency), never the
/// legacy `DetailRow`. The detail view wires every interaction closure to its
/// private `RowTarget` logic.
///
/// NOT in this task: selection / keyboard (Task 11), drag/drop (Task 14). Rows
/// render plain; double-click open works through `onDoubleTap`.
struct CustomTableView: View {
    let groups: [ResolvedGroup]
    let columns: [ResolvedColumn]
    let layout: ColumnLayout
    let schema: [PropertyDefinition]

    let index: PommoraIndex?
    let relationResolver: (String) -> (icon: String, title: String)?
    let onDoubleTap: (ViewItem) -> Void
    let commit: (ViewItem, PropertyDefinition, PropertyValue?) -> Void
    /// Per-page context menu (Title cell). Returns `AnyView` so the detail view
    /// can build its `RowTarget`-driven menu without `CustomTableView` knowing
    /// the entity types.
    let pageMenu: (ViewItem) -> AnyView
    /// Per-group container context menu (Collection / Set disclosure rows).
    let groupMenu: (ResolvedGroup) -> AnyView

    /// Header-interaction persistence (Task 10) — each closes over the detail
    /// view's active view + container so the header never touches a manager:
    ///   - `persistWidth` — write a column's final width after a resize ends.
    ///   - `persistOrder` — write a reordered `propertyOrder` after a drop.
    ///   - `hideColumn`   — append a column id to `hiddenProperties`.
    let persistWidth: (_ colID: String, _ width: Double) -> Void
    let persistOrder: (_ newOrder: [String]) -> Void
    let hideColumn: (_ colID: String) -> Void

    /// Disclosure state — collapsed group ids. Seeds expanded (every group open);
    /// survives the frequent `groups` recompute since it's keyed by stable id.
    /// This local toggle is the live collapse truth today; persisting it back to
    /// the SavedView's `collapsedGroups` (and seeding from `ResolvedGroup.isCollapsed`)
    /// is Task 12's ActiveViewStore wiring.
    @State private var collapsed: Set<String> = []

    private var totalWidth: CGFloat { CGFloat(layout.totalWidth) }

    var body: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        let entries = renderEntries
                        ForEach(entries) { entry in
                            row(for: entry)
                        }
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    TableHeaderRow(
                        columns: columns,
                        layout: layout,
                        rowHeight: TableRowView.rowHeight,
                        persistWidth: persistWidth,
                        persistOrder: persistOrder,
                        hideColumn: hideColumn)
                }
            }
            .frame(width: totalWidth)
        }
    }

    @ViewBuilder
    private func row(for entry: RenderEntry) -> some View {
        switch entry.kind {
        case .group(let group, let depth):
            TableGroupRow(
                group: group,
                depth: depth,
                isExpanded: !collapsed.contains(group.id),
                totalWidth: totalWidth,
                onToggle: { toggle(group.id) },
                menu: groupMenu
            )
        case .item(let item, let visualIndex):
            TableRowView(
                item: item,
                columns: columns,
                widths: layout.widths,
                schema: schema,
                visualIndex: visualIndex,
                index: index,
                relationResolver: relationResolver,
                onDoubleTap: onDoubleTap,
                commit: { def, value in commit(item, def, value) },
                menu: pageMenu
            )
        }
    }

    private func toggle(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    // MARK: - Flat render entries

    /// A flattened, ordered render list — group headers + item rows in display
    /// order. Item rows carry a RUNNING visual index (global across the whole
    /// table) so the alternating quinary stripe stays continuous. Collapsed
    /// groups emit their header but skip their items + child groups.
    private var renderEntries: [RenderEntry] {
        var entries: [RenderEntry] = []
        var visualIndex = 0
        for group in groups {
            appendGroup(group, depth: 0, into: &entries, visualIndex: &visualIndex)
        }
        return entries
    }

    private func appendGroup(
        _ group: ResolvedGroup,
        depth: Int,
        into entries: inout [RenderEntry],
        visualIndex: inout Int
    ) {
        // The headerless ungrouped band (collection scope with zero Sets, or the
        // vault-root trailing band) emits its items directly — no group row.
        let isHeaderless = group.kind == .ungrouped && group.title.isEmpty
        if !isHeaderless {
            entries.append(RenderEntry(id: "group-\(group.id)", kind: .group(group, depth)))
        }

        // Collapsed groups show the header only.
        guard isHeaderless || !collapsed.contains(group.id) else { return }

        for item in group.items {
            entries.append(RenderEntry(id: "item-\(item.id)", kind: .item(item, visualIndex)))
            visualIndex += 1
        }
        for child in group.children ?? [] {
            appendGroup(child, depth: depth + 1, into: &entries, visualIndex: &visualIndex)
        }
    }
}

// MARK: - Render entry

/// One flattened render unit — a group header (with indent depth) or an item row
/// (with its running visual index for stripe parity). Identifiable so the
/// `ForEach` over the flat list diffs cleanly.
private struct RenderEntry: Identifiable {
    enum Kind {
        case group(ResolvedGroup, Int)
        case item(ViewItem, Int)
    }

    let id: String
    let kind: Kind
}
