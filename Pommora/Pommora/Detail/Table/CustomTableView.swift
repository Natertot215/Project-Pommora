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
/// Inputs are `ViewItem` + `ResolvedGroup` (the pipeline currency). The detail
/// view wires every interaction closure to its private `RowTarget` logic.
///
/// Selection / keyboard (Task 11) and row drag/drop (Task 14) are wired here;
/// double-click open works through `onDoubleTap`. All drag mechanics route
/// through the injected `RowDragCoordinator` (the controller's swap seam).
struct CustomTableView: View {
    let groups: [ResolvedGroup]
    let columns: [ResolvedColumn]
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
            _ anchorID: String?, _ sourceIndices: IndexSet
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
    /// Vertical scroll anchor — drives scroll-into-view on keyboard moves AND the
    /// drag edge auto-scroll nudge.
    @State private var scrollPosition = ScrollPosition()
    /// The vertical scroll viewport's GLOBAL frame — captured on the scroll
    /// content so the edge auto-scroll nudge knows where the top/bottom proximity
    /// bands sit relative to the (global) drop location.
    @State private var viewportFrame: CGRect = .zero
    @FocusState private var tableFocused: Bool

    /// Live column geometry — OWNED here (not rebuilt by the parent every body
    /// recompute, which would clobber an in-flight resize). Seeded from `columns`
    /// at init and re-seeded only when the column identity/order changes (see
    /// `.onChange(of: columnIdentities)`); the persisted-width re-seed survives
    /// because the resolved columns carry their persisted widths.
    @State private var layout: ColumnLayout

    init(
        groups: [ResolvedGroup],
        columns: [ResolvedColumn],
        schema: [PropertyDefinition],
        index: PommoraIndex?,
        relationResolver: @escaping (String) -> (icon: String, title: String)?,
        onDoubleTap: @escaping (ViewItem) -> Void,
        commit: @escaping (ViewItem, PropertyDefinition, PropertyValue?) -> Void,
        pageMenu: @escaping (ViewItem) -> AnyView,
        groupMenu: @escaping (ResolvedGroup) -> AnyView,
        persistWidth: @escaping (_ colID: String, _ width: Double) -> Void,
        persistOrder: @escaping (_ newOrder: [String]) -> Void,
        hideColumn: @escaping (_ colID: String) -> Void,
        persistCollapsed: @escaping (_ collapsedIDs: [String]) -> Void,
        dragCoordinator: RowDragCoordinator,
        buildDropContext:
            @escaping (
                _ draggedItems: [ViewItem], _ targetGroup: ResolvedGroup, _ insertionIndex: Int,
                _ anchorID: String?, _ sourceIndices: IndexSet
            ) -> RowDragCoordinator.DropContext?
    ) {
        self.groups = groups
        self.columns = columns
        self.schema = schema
        self.index = index
        self.relationResolver = relationResolver
        self.onDoubleTap = onDoubleTap
        self.commit = commit
        self.pageMenu = pageMenu
        self.groupMenu = groupMenu
        self.persistWidth = persistWidth
        self.persistOrder = persistOrder
        self.hideColumn = hideColumn
        self.persistCollapsed = persistCollapsed
        self.dragCoordinator = dragCoordinator
        self.buildDropContext = buildDropContext
        _layout = State(initialValue: ColumnLayout(columns: columns))
    }

    /// The column identity/order signature — re-seeding the layout keys off this,
    /// so a width-resize (which never changes identity/order) can't trigger a
    /// clobbering rebuild mid-gesture.
    private var columnIdentities: [String] { columns.map(\.id) }

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
                    // Required for `scrollPosition.scrollTo(id:)` to resolve the
                    // per-row `.id("item-…")` (keyboard-nav follow, type-select,
                    // drag edge-scroll); without it the scroll-into-view is dead.
                    .scrollTargetLayout()
                }
                .scrollPosition($scrollPosition)
                // The scroll viewport's GLOBAL frame — the fixed window the edge
                // auto-scroll bands sit at the top/bottom of. `DropSession.location`
                // is local to each drop element, so the whole live-drag geometry
                // works in `.global`: row/group frames are captured in `.global`
                // and the location is lifted to global via the firing element's
                // own global frame.
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    viewportFrame = $0
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
        .focusable()
        // Keyboard focus stays live (arrows / type-select) but the whole-pane
        // blue focus ring is suppressed — per-row selection accent is the only
        // selection signal. (macOS 14+ API.)
        .focusEffectDisabled()
        .focused($tableFocused)
        .onModifierKeysChanged { _, new in modifiers = new }
        .onMoveCommand { direction in handleMove(direction) }
        .onKeyPress(.return) { handleReturn() }
        .onKeyPress(characters: .alphanumerics) { handleTypeSelect($0.characters) }
        .onChange(of: flattenedOrder) { selection.order = $1 }
        // Re-seed the owned layout only when the column set/order changes — a
        // width-only resize keeps the same identities, so the live geometry
        // (mid-resize widths) survives a parent body recompute.
        .onChange(of: columnIdentities) { layout = ColumnLayout(columns: columns) }
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
            // Capture this group header's GLOBAL frame so the hover math can
            // highlight it as a move / rewrite target off the (global) drop location.
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                dragCoordinator.setGroupFrame(group.id, $0)
            }
            // Group rows are drop TARGETS only — never `.draggable`. A drop here
            // appends to the group's end (move / rewrite / same-container reorder).
            .dropDestination(for: ViewRowDragPayload.self, isEnabled: true) { payloads, _ in
                commitDrop(payloads, ontoGroup: group)
            }
            .onDropSessionUpdated { session in
                updateDropFromLocation(session, elementFrame: dragCoordinator.groupFrames[group.id])
            }
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
            // Capture this row's GLOBAL frame — the live insertion line position is
            // hit-tested from these frames + the (global) drop location.
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                dragCoordinator.setRowFrame(item.id, $0)
            }
            // Only PAGE rows are drag SOURCES. The payload carries the active
            // selection when the dragged row is selected (native multi-drag bound
            // to the Task-11 selection set), else just this row. `beginDrag`
            // stamps the dragged identity for the hover math (the drop-session
            // payload is nil mid-flight for per-row `.draggable`).
            .draggable(dragPayload(for: item)) {
                // A lightweight drag preview that ALSO stamps the dragged identity
                // for the location-driven hover math (the drop-session payload is
                // nil mid-flight for per-row `.draggable`). The preview's appearance
                // coincides with drag start.
                dragPreview(for: item)
                    .onAppear { dragCoordinator.beginDrag(dragPayload(for: item).pageIDs) }
            }
            .overlay(alignment: .top) { insertionLine(forItemID: item.id) }
            // Page rows are also row-level drop targets (between-rows reorder).
            .dropDestination(for: ViewRowDragPayload.self, isEnabled: true) { payloads, _ in
                commitDrop(payloads, ontoItem: item)
            }
            .onDropSessionUpdated { session in
                updateDropFromLocation(session, elementFrame: dragCoordinator.rowFrames[item.id])
            }
        }
    }

    private func toggle(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        persistCollapsed(Array(collapsed))
    }

    // MARK: - Drag / drop (Task 14)

    /// The drag preview chip — the dragged page's icon + title, plus a count badge
    /// when a multi-row selection is in flight.
    @ViewBuilder
    private func dragPreview(for item: ViewItem) -> some View {
        let ids = dragPayload(for: item).pageIDs
        HStack(spacing: PUI.Spacing.sm) {
            Image(systemName: item.page.frontmatter.icon ?? "doc.text")
            Text(item.page.title).lineLimit(1)
            if ids.count > 1 {
                Text("\(ids.count)")
                    .font(.caption)
                    .padding(.horizontal, PUI.Spacing.sm)
                    .background(.tint, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .font(.caption)
        .padding(.horizontal, PUI.Spacing.md)
        .padding(.vertical, PUI.Spacing.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

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

    /// Drive the insertion line + group highlight off the drop session's LOCATION,
    /// hit-tested against the captured row/group frames — NOT off `draggedItemIDs`
    /// (nil for per-row `.draggable`). `DropSession.location` is local to the
    /// firing element, so it's lifted to the shared GLOBAL space using that
    /// element's captured global frame. Edge auto-scroll is nudged from the same
    /// global location.
    private func updateDropFromLocation(_ session: DropSession, elementFrame: CGRect?) {
        switch session.phase {
        case .exiting, .ended, .dataTransferCompleted:
            dragCoordinator.update(nil)
            return
        default:
            break
        }

        // Lift the element-local drop point into the global space the registry
        // is captured in. Without the firing element's frame we can't place it.
        guard let elementFrame else {
            dragCoordinator.update(nil)
            return
        }
        let location = CGPoint(
            x: elementFrame.minX + session.location.x,
            y: elementFrame.minY + session.location.y)
        autoScrollIfNearEdge(globalY: location.y)

        // The dragged identity is known from the drag-start stamp, not the
        // session payload. Resolve it to the active ViewItems for the planner.
        let draggedIDs = dragCoordinator.draggedIDs
        let dragged = flattenedViewItems.filter { draggedIDs.contains($0.id) }
        guard !dragged.isEmpty else {
            dragCoordinator.update(nil)
            return
        }

        // 1) Is the location over a page row? Hit-test that row's enclosing group
        //    and compute the vertical-midpoint insertion index within it.
        if let item = rowUnder(location),
            let group = enclosingGroup(ofItemID: item.id)
        {
            let rows = rowFrames(in: group)
            // Past the last CAPTURED row, append at the true container end — the
            // frame registry only holds on-screen rows (LazyVStack virtualization),
            // so the last captured index can sit mid-group when trailing rows are
            // scrolled out.
            let index: Int
            if let last = rows.last, location.y >= last.frame.maxY {
                index = group.items.count
            } else {
                index =
                    RowDragGeometry.insertionIndex(locationY: location.y, rows: rows)
                    ?? (group.items.firstIndex(where: { $0.id == item.id }) ?? group.items.count)
            }
            let sourceIndices = IndexSet(
                dragged.compactMap { d in group.items.firstIndex(where: { $0.id == d.id }) })
            dragCoordinator.update(
                buildDropContext(dragged, group, index, anchorID(in: group, at: index), sourceIndices)
            )
            return
        }

        // 2) Otherwise, is the location over a group header? → append to its end
        //    (move / rewrite / same-container reorder, exactly as the drop path).
        if let group = groupUnder(location) {
            let sourceIndices = IndexSet(
                dragged.compactMap { d in group.items.firstIndex(where: { $0.id == d.id }) })
            dragCoordinator.update(
                buildDropContext(dragged, group, group.items.count, nil, sourceIndices))
            return
        }

        dragCoordinator.update(nil)
    }

    /// The captured row frames for a group's items, in render order — feeds the
    /// pure vertical-midpoint insertion math.
    private func rowFrames(in group: ResolvedGroup) -> [RowDragGeometry.RowFrame] {
        group.items.enumerated().compactMap { idx, item in
            guard let frame = dragCoordinator.rowFrames[item.id] else { return nil }
            return RowDragGeometry.RowFrame(id: item.id, frame: frame, indexInGroup: idx)
        }
    }

    /// The page row whose captured frame contains `location`, if any.
    private func rowUnder(_ location: CGPoint) -> ViewItem? {
        flattenedViewItems.first(where: { item in
            dragCoordinator.rowFrames[item.id]?.contains(location) ?? false
        })
    }

    /// The group header whose captured frame contains `location`, if any.
    private func groupUnder(_ location: CGPoint) -> ResolvedGroup? {
        func search(_ group: ResolvedGroup) -> ResolvedGroup? {
            if dragCoordinator.groupFrames[group.id]?.contains(location) ?? false { return group }
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
        return buildDropContext(
            draggedAnywhere, group, insertionIndex, anchorID(in: group, at: insertionIndex),
            sourceIndices)
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
        return buildDropContext(dragged, group, group.items.count, nil, sourceIndices)
    }

    /// The page id a drop at `index` within `group.items` lands BEFORE — the
    /// reorder anchor — or nil when `index` is the container end (append).
    private func anchorID(in group: ResolvedGroup, at index: Int) -> String? {
        group.items.indices.contains(index) ? group.items[index].id : nil
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

    /// Edge auto-scroll during a row drag. macOS 26's `ScrollView` does NOT
    /// natively auto-scroll for a custom `.draggable`/`dropDestination` payload
    /// (native auto-scroll only kicks in for `List`/`Table` row reordering), so
    /// this nudges the scroll edge when the drag's global Y sits inside a
    /// `Self.edgeBand`-tall band at the viewport's top or bottom. Each nudge
    /// brings the nearest off-edge captured row into view; repeated update
    /// callbacks (the drop session fires continuously while hovering) keep it
    /// scrolling as long as the cursor dwells in the band.
    private func autoScrollIfNearEdge(globalY: Double) {
        guard viewportFrame.height > 0 else { return }
        // Find the nearest row to the relevant edge and bring it into view — a
        // reliable nudge that doesn't depend on reading the live content offset
        // (which `ScrollPosition` doesn't expose once positioned by id).
        let topBand = viewportFrame.minY...(viewportFrame.minY + Self.edgeBand)
        let bottomBand = (viewportFrame.maxY - Self.edgeBand)...viewportFrame.maxY
        if topBand.contains(globalY) {
            nudgeToward(.top)
        } else if bottomBand.contains(globalY) {
            nudgeToward(.bottom)
        }
    }

    /// Scroll the row just beyond the given edge into view — the edge auto-scroll
    /// step. The `.global`-space row frames let us pick the row whose midpoint
    /// sits just outside the viewport on that side and scroll it to center.
    private func nudgeToward(_ edge: Edge) {
        let frames = flattenedViewItems.compactMap { item -> (String, CGRect)? in
            guard let f = dragCoordinator.rowFrames[item.id] else { return nil }
            return (item.id, f)
        }
        guard !frames.isEmpty else {
            scrollPosition.scrollTo(edge: edge)
            return
        }
        // Bring the currently-topmost (or bottommost) captured row a little further
        // into view — only rows near the visible window have live frames, so this
        // advances the scroll one step toward the edge each callback.
        let sorted = frames.sorted { $0.1.midY < $1.1.midY }
        let targetID = edge == .top ? sorted.first?.0 : sorted.last?.0
        if let targetID { scrollPosition.scrollTo(id: "item-\(targetID)", anchor: .center) }
    }

    /// The top/bottom proximity band (pt) that triggers the edge auto-scroll.
    private static let edgeBand: CGFloat = 28

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
