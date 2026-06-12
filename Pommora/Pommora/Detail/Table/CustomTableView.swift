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
    /// Persists the full collapsed-group id set after a chevron toggle into the
    /// active SavedView's `collapsedGroups` (Task 13). The detail view closes
    /// over its active view + container; the table never touches a manager.
    let persistCollapsed: (_ collapsedIDs: [String]) -> Void

    /// Disclosure state — collapsed group ids. SEEDED from the active view's
    /// persisted `collapsedGroups` (carried in on `ResolvedGroup.isCollapsed`)
    /// and kept in sync as `groups` recomputes; each toggle persists the full
    /// set back through `persistCollapsed` (Task 13). Keyed by stable id, so it
    /// survives the frequent `groups` recompute.
    @State private var collapsed: Set<String> = []

    /// Net-new selection + keyboard-nav state (Task 11). Self-contained here;
    /// persisting active-view selection is out of scope (Task 12).
    @State private var selection = TableSelectionModel()
    /// Live modifier mask, tracked via `onModifierKeysChanged` so a row's tap
    /// closure can resolve plain / ⌘ / ⇧ at click time.
    @State private var modifiers: EventModifiers = []
    /// Type-select buffer + its reset deadline (chars accumulate, ~0.5s idle clears).
    @State private var typeBuffer = ""
    @State private var typeBufferStamp = Date.distantPast
    /// Vertical scroll anchor — drives scroll-into-view on keyboard moves.
    @State private var scrollPosition = ScrollPosition()
    @FocusState private var tableFocused: Bool

    private var totalWidth: CGFloat { CGFloat(layout.totalWidth) }

    var body: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        let entries = renderEntries
                        ForEach(entries) { entry in
                            row(for: entry)
                                .id(entry.id)
                        }
                    }
                }
                .scrollPosition($scrollPosition)
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
        .focusable()
        .focused($tableFocused)
        .onModifierKeysChanged { _, new in modifiers = new }
        .onMoveCommand { direction in handleMove(direction) }
        .onKeyPress(.return) { handleReturn() }
        .onKeyPress(characters: .alphanumerics) { handleTypeSelect($0.characters) }
        .onChange(of: flattenedOrder) { selection.order = $1 }
        .task { selection.order = flattenedOrder }
        // Seed collapse state from the active view's persisted `collapsedGroups`
        // (carried in via `ResolvedGroup.isCollapsed`). Re-seeds if the persisted
        // set changes out-of-band (e.g. another surface writes the view).
        .task(id: persistedCollapsedIDs) { collapsed = persistedCollapsedIDs }
    }

    /// The collapsed ids the resolver baked in from the SavedView's
    /// `collapsedGroups` — the seed + live-sync source for local `collapsed`.
    private var persistedCollapsedIDs: Set<String> {
        var ids: Set<String> = []
        func walk(_ group: ResolvedGroup) {
            if group.isCollapsed { ids.insert(group.id) }
            for child in group.children ?? [] { walk(child) }
        }
        for group in groups { walk(group) }
        return ids
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
                menu: pageMenu,
                isSelected: selection.selection.contains(item.id),
                onSelect: { handleSelect($0) }
            )
        }
    }

    private func toggle(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        persistCollapsed(Array(collapsed))
    }

    // MARK: - Selection / keyboard handlers

    /// Resolve the click kind from the live modifier mask, then mutate selection.
    private func handleSelect(_ item: ViewItem) {
        tableFocused = true
        let kind: TableSelectionModel.ClickKind
        if modifiers.contains(.command) {
            kind = .toggle
        } else if modifiers.contains(.shift) {
            kind = .range
        } else {
            kind = .plain
        }
        selection.click(item.id, kind: kind)
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        let dir: TableSelectionModel.MoveDirection
        switch direction {
        case .up: dir = .up
        case .down: dir = .down
        default: return
        }
        if let moved = selection.move(dir, extend: modifiers.contains(.shift)) {
            scrollToItem(moved)
        }
    }

    private func handleReturn() -> KeyPress.Result {
        guard let id = selection.openTargetID, let item = item(forID: id) else { return .ignored }
        onDoubleTap(item)
        return .handled
    }

    private func handleTypeSelect(_ chars: String) -> KeyPress.Result {
        let now = Date()
        // Reset the buffer if the last keystroke was more than ~0.5s ago.
        if now.timeIntervalSince(typeBufferStamp) > 0.5 { typeBuffer = "" }
        typeBufferStamp = now
        typeBuffer += chars
        guard
            let id = selection.typeSelectTarget(
                prefix: typeBuffer,
                title: { item(forID: $0)?.page.title })
        else { return .ignored }
        selection.click(id, kind: .plain)
        scrollToItem(id)
        return .handled
    }

    private func scrollToItem(_ id: String) {
        scrollPosition.scrollTo(id: "item-\(id)", anchor: .center)
    }

    private func item(forID id: String) -> ViewItem? {
        flattenedViewItems.first(where: { $0.id == id })
    }

    // MARK: - Flattened item order

    /// The linear id sequence in EXACT render order — collapsed groups contribute
    /// no items, matching `renderEntries`. Drives ⇧-range, arrow nav, type-select.
    private var flattenedOrder: [String] { flattenedViewItems.map(\.id) }

    private var flattenedViewItems: [ViewItem] {
        var items: [ViewItem] = []
        for group in groups { appendItems(group, into: &items) }
        return items
    }

    private func appendItems(_ group: ResolvedGroup, into items: inout [ViewItem]) {
        let isHeaderless = group.kind == .ungrouped && group.title.isEmpty
        guard isHeaderless || !collapsed.contains(group.id) else { return }
        items.append(contentsOf: group.items)
        for child in group.children ?? [] { appendItems(child, into: &items) }
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
