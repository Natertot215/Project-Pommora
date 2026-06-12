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
/// Selection / keyboard (Task 11) and row drag/drop (Task 14) are wired here;
/// double-click open works through `onDoubleTap`. All drag mechanics route
/// through the injected `RowDragCoordinator` (the controller's swap seam).
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

    /// Row drag/drop seam (Task 14). The coordinator owns the swappable drag
    /// mechanic + the commit closures; `buildDropContext` resolves a drop into a
    /// planner-ready context using the detail view's scope knowledge (active
    /// view's group/sort + structural-parent mapping). Both injected by the
    /// detail view, which owns the manager calls.
    let dragCoordinator: RowDragCoordinator
    let buildDropContext:
        (
            _ draggedItems: [ViewItem], _ targetGroup: ResolvedGroup, _ insertionIndex: Int,
            _ sourceIndices: IndexSet
        ) -> RowDragCoordinator.DropContext?

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
                isDropTarget: dragCoordinator.highlightedGroupID == group.id,
                totalWidth: totalWidth,
                onToggle: { toggle(group.id) },
                menu: groupMenu
            )
            // Group rows are drop TARGETS only — never `.draggable`. A drop here
            // appends to the group's end (move / rewrite / same-container reorder).
            .dropDestination(for: ViewRowDragPayload.self, isEnabled: true) { payloads, _ in
                commitDrop(payloads, ontoGroup: group)
            }
            .onDropSessionUpdated { session in updateDrop(session, ontoGroup: group) }
            // Auto-expand a collapsed group on hover-dwell so the drag can target
            // a row inside it; native spring-loading drives the dwell.
            .springLoadingBehavior(collapsed.contains(group.id) ? .enabled : .disabled)
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
            // Only PAGE rows are drag SOURCES. The payload carries the active
            // selection when the dragged row is selected (native multi-drag bound
            // to the Task-11 selection set), else just this row.
            .draggable(dragPayload(for: item))
            .overlay(alignment: .top) { insertionLine(forItemID: item.id) }
            // Page rows are also row-level drop targets (between-rows reorder).
            .dropDestination(for: ViewRowDragPayload.self, isEnabled: true) { payloads, _ in
                commitDrop(payloads, ontoItem: item)
            }
            .onDropSessionUpdated { session in updateDrop(session, ontoItem: item) }
        }
    }

    private func toggle(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        persistCollapsed(Array(collapsed))
    }

    // MARK: - Drag / drop (Task 14)

    /// The payload for dragging `item`: the full selection when `item` is selected
    /// (native multi-drag bound to the Task-11 selection), else just this row.
    private func dragPayload(for item: ViewItem) -> ViewRowDragPayload {
        if selection.selection.contains(item.id) {
            // Preserve render order so reorder offsets stay meaningful.
            let ids = flattenedOrder.filter { selection.selection.contains($0) }
            return ViewRowDragPayload(pageIDs: ids.isEmpty ? [item.id] : ids)
        }
        return ViewRowDragPayload(pageIDs: [item.id])
    }

    /// Drop landing on a page row → reorder/move/rewrite relative to that row's
    /// group, inserting at the row's index within its group.
    private func commitDrop(_ payloads: [ViewRowDragPayload], ontoItem item: ViewItem) {
        guard let context = dropContext(payloads, ontoItem: item) else { return }
        dragCoordinator.drop(payload: mergedPayload(payloads), context: context)
    }

    /// Drop landing on a group header → append to the group's end.
    private func commitDrop(_ payloads: [ViewRowDragPayload], ontoGroup group: ResolvedGroup) {
        guard let context = dropContext(payloads, ontoGroup: group) else { return }
        dragCoordinator.drop(payload: mergedPayload(payloads), context: context)
    }

    private func updateDrop(_ session: DropSession, ontoItem item: ViewItem) {
        switch session.phase {
        case .exiting, .ended, .dataTransferCompleted:
            dragCoordinator.update(nil)
        default:
            let payloads = draggedPayloads(in: session)
            dragCoordinator.update(dropContext(payloads, ontoItem: item))
        }
    }

    private func updateDrop(_ session: DropSession, ontoGroup group: ResolvedGroup) {
        switch session.phase {
        case .exiting, .ended, .dataTransferCompleted:
            dragCoordinator.update(nil)
        default:
            let payloads = draggedPayloads(in: session)
            dragCoordinator.update(dropContext(payloads, ontoGroup: group))
        }
    }

    /// Best-effort in-flight payload from the local drag session (same-app drag),
    /// so the insertion line / highlight resolve before the data fully transfers.
    private func draggedPayloads(in session: DropSession) -> [ViewRowDragPayload] {
        guard let local = session.localSession else { return [] }
        let ids = local.draggedItemIDs(for: String.self)
        return ids.isEmpty ? [] : [ViewRowDragPayload(pageIDs: ids)]
    }

    private func mergedPayload(_ payloads: [ViewRowDragPayload]) -> ViewRowDragPayload {
        ViewRowDragPayload(pageIDs: payloads.flatMap(\.pageIDs))
    }

    /// Build a planner context for a row-targeted drop.
    private func dropContext(
        _ payloads: [ViewRowDragPayload], ontoItem item: ViewItem
    ) -> RowDragCoordinator.DropContext? {
        let ids = payloads.flatMap(\.pageIDs)
        guard let group = enclosingGroup(ofItemID: item.id) else { return nil }
        let dragged = group.items.filter { ids.contains($0.id) }
        let draggedAnywhere =
            dragged.isEmpty ? flattenedViewItems.filter { ids.contains($0.id) } : dragged
        guard !draggedAnywhere.isEmpty else { return nil }
        let insertionIndex = group.items.firstIndex(where: { $0.id == item.id }) ?? group.items.count
        let sourceIndices = IndexSet(
            draggedAnywhere.compactMap { d in group.items.firstIndex(where: { $0.id == d.id }) })
        return buildDropContext(draggedAnywhere, group, insertionIndex, sourceIndices)
    }

    /// Build a planner context for a group-header-targeted drop (append to end).
    private func dropContext(
        _ payloads: [ViewRowDragPayload], ontoGroup group: ResolvedGroup
    ) -> RowDragCoordinator.DropContext? {
        let ids = payloads.flatMap(\.pageIDs)
        let dragged = flattenedViewItems.filter { ids.contains($0.id) }
        guard !dragged.isEmpty else { return nil }
        let sourceIndices = IndexSet(
            dragged.compactMap { d in group.items.firstIndex(where: { $0.id == d.id }) })
        return buildDropContext(dragged, group, group.items.count, sourceIndices)
    }

    /// The resolved group whose `items` include `id` (searches nested children).
    private func enclosingGroup(ofItemID id: String) -> ResolvedGroup? {
        func search(_ group: ResolvedGroup) -> ResolvedGroup? {
            if group.items.contains(where: { $0.id == id }) { return group }
            for child in group.children ?? [] {
                if let found = search(child) { return found }
            }
            return nil
        }
        for group in groups {
            if let found = search(group) { return found }
        }
        return nil
    }

    /// The reorder insertion divider drawn above a page row when the coordinator's
    /// insertion marker targets that row's group + index.
    @ViewBuilder
    private func insertionLine(forItemID id: String) -> some View {
        if let marker = dragCoordinator.insertion,
            let group = enclosingGroup(ofItemID: id),
            group.id == marker.groupID,
            group.items.indices.contains(marker.index),
            group.items[marker.index].id == id
        {
            Rectangle()
                .fill(.tint)
                .frame(height: 2)
        }
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
