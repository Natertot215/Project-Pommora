import SwiftUI

/// The Gallery renderer — parity sibling of `ViewOutlineTable`. Consumes the
/// same `[ResolvedGroup]` pipeline currency + the same interaction closures the
/// detail view wires for the table, so the two renderers share every commit
/// path (cell edits, drag, menus, collapse persistence).
///
/// Layout: each `ResolvedGroup` becomes a collapsible section (disclosure
/// header, parity with the table's group rows); the section body is a
/// `LazyVGrid` of `GalleryCard`s at `cardSize.columnsPerRow` per row (8 / 6 / 4
/// for small / medium / large). In **vault scope** the pipeline nests Sets under
/// a Collection group, so each Collection section flattens via
/// `group.flattenedItems` (ONE section level per Collection — Sets folded in,
/// each card carrying its `setLabel` chip).
///
/// Cards join the Task-14 drag machinery: each is `draggable` with the same
/// `ViewRowDragPayload`, and `dropDestination` routes through the SAME
/// `dragCoordinator` + `buildDropContext` the table uses (reflow when the active
/// view's sort is manual). Selection is a self-contained `ViewSelectionModel`
/// (page-id set) — sidebar selection is untouched.
struct GalleryView: View {
    let groups: [ResolvedGroup]
    let view: SavedView
    let schema: [PropertyDefinition]
    let nexus: Nexus
    let index: PommoraIndex?

    let relationResolver: (String) -> (icon: String, title: String)?
    let onDoubleTap: (ViewItem) -> Void
    let commit: (ViewItem, PropertyDefinition, PropertyValue?) -> Void
    let onRename: (ViewItem) -> Void
    let onEditIcon: (ViewItem) -> Void
    let pageMenu: (ViewItem) -> AnyView
    let groupMenu: (ResolvedGroup) -> AnyView
    /// Cover-area menu for a card (Set / Change / Remove Cover). The detail view
    /// builds it with the page's container ref so the cover writes route to the
    /// right vault / collection / set.
    let coverMenu: (ViewItem) -> AnyView
    let persistCollapsed: (_ collapsedIDs: [String]) -> Void

    let dragCoordinator: RowDragCoordinator
    let buildDropContext:
        (
            _ draggedItems: [ViewItem], _ targetGroup: ResolvedGroup, _ insertionIndex: Int,
            _ anchorID: String?
        ) -> RowDragCoordinator.DropContext?

    @State private var collapsed: Set<String> = []
    @State private var selection = ViewSelectionModel()

    private var cardSize: CardSize { view.cardSize ?? .medium }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: PUI.Spacing.xl, alignment: .top),
            count: cardSize.columnsPerRow)
    }

    /// Flattened page-id order across every section — feeds the selection model
    /// so keyboard / range selection stays consistent across recomputes.
    private var flattenedOrder: [String] {
        groups.flatMap(\.flattenedItems).map(\.id)
    }

    private var persistedCollapsedIDs: Set<String> {
        Set(groups.filter(\.isCollapsed).map(\.id))
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: PUI.Spacing.xl) {
                ForEach(groups) { group in
                    section(for: group)
                }
            }
            .padding(PUI.Spacing.xl)
        }
        .onChange(of: flattenedOrder) { selection.order = $1 }
        .task { selection.order = flattenedOrder }
        .task(id: persistedCollapsedIDs) { collapsed = persistedCollapsedIDs }
    }

    // MARK: - Section

    @ViewBuilder
    private func section(for group: ResolvedGroup) -> some View {
        // The headerless ungrouped band renders cards with no disclosure header
        // (parity with the table's headerless root band).
        if group.kind == .ungrouped {
            grid(for: group)
        } else {
            VStack(alignment: .leading, spacing: PUI.Spacing.md) {
                header(for: group)
                if !collapsed.contains(group.id) {
                    grid(for: group)
                }
            }
        }
    }

    private func header(for group: ResolvedGroup) -> some View {
        let isCollapsed = collapsed.contains(group.id)
        return HStack(spacing: PUI.Spacing.sm) {
            Button {
                toggleCollapse(group.id)
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Text(group.title)
                .font(.headline)
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, PUI.Spacing.xs)
        .padding(.horizontal, PUI.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(dragCoordinator.highlightedGroupID == group.id ? Color.accentColor.opacity(0.15) : .clear)
        )
        .contextMenu { groupMenu(group) }
    }

    private func toggleCollapse(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        persistCollapsed(Array(collapsed))
    }

    // MARK: - Grid

    private func grid(for group: ResolvedGroup) -> some View {
        // Vault scope nests Sets under Collection groups; the gallery flattens to
        // ONE section level so no Set page is dropped.
        let items = group.flattenedItems
        return LazyVGrid(columns: gridColumns, alignment: .leading, spacing: PUI.Spacing.xl) {
            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                card(for: item, in: group, at: offset)
            }
        }
    }

    private func card(for item: ViewItem, in group: ResolvedGroup, at offset: Int) -> some View {
        GalleryCard(
            item: item,
            view: view,
            schema: schema,
            nexus: nexus,
            index: index,
            isSelected: selection.selection.contains(item.id),
            relationResolver: relationResolver,
            commit: { def, value in commit(item, def, value) },
            onSelect: { selection.click(item.id, kind: .plain) },
            onOpen: { onDoubleTap(item) },
            onRename: { onRename(item) },
            onEditIcon: { onEditIcon(item) },
            pageMenu: { pageMenu(item) },
            coverMenu: view.showCover == true ? { coverMenu(item) } : nil
        )
        // Capture this card's GLOBAL frame — the live insertion capsule is
        // hit-tested from these frames + the (global) drop location (the
        // coordinator's `cardFrames` registry).
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            dragCoordinator.setCardFrame(item.id, $0)
        }
        // The leading-edge insertion capsule + trailing append marker, drawn from
        // the coordinator's observable insertion state (same source as the table).
        .overlay(alignment: .leading) { insertionCapsule(forItemID: item.id, in: group) }
        .overlay(alignment: .trailing) { appendCapsule(forItemID: item.id, in: group) }
        .draggable(ViewRowDragPayload(pageIDs: dragIDs(for: item))) {
            // Stamp the dragged identity at drag start — the drop-session payload
            // is nil mid-flight for per-card `.draggable`, so the hover math reads
            // `draggedIDs` instead (parity with the table's preview-onAppear stamp).
            dragPreview(for: item)
                .onAppear { dragCoordinator.beginDrag(dragIDs(for: item)) }
        }
        .dropDestination(for: ViewRowDragPayload.self) { payloads, _ in
            handleDrop(payloads, onto: group, at: offset)
        }
        .onDropSessionUpdated { session in
            updateDropFromLocation(session, onto: group, elementFrame: dragCoordinator.cardFrames[item.id])
        }
    }

    /// A lightweight drag preview that also stamps the dragged identity.
    private func dragPreview(for item: ViewItem) -> some View {
        let ids = dragIDs(for: item)
        return HStack(spacing: PUI.Spacing.sm) {
            PageIconGlyph(icon: item.page.frontmatter.icon)
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

    /// The drag payload's pages: the full selection when the dragged card is
    /// selected (parity with the table's multi-drag), else just this card.
    private func dragIDs(for item: ViewItem) -> [String] {
        if selection.selection.contains(item.id) {
            // Preserve render (flow) order so reorder offsets stay meaningful —
            // `selection.selection` is an unordered Set.
            let ids = flattenedOrder.filter { selection.selection.contains($0) }
            return ids.isEmpty ? [item.id] : ids
        }
        return [item.id]
    }

    /// Route a card drop through the shared coordinator: build a DropContext at
    /// the target card's flattened index, then commit via `coordinator.drop`.
    private func handleDrop(_ payloads: [ViewRowDragPayload], onto group: ResolvedGroup, at insertionIndex: Int) -> Bool
    {
        guard let payload = payloads.first else { return false }
        // Resolve the dragged items across ALL groups (parity with the table's
        // `acceptDrop`), so a CROSS-group drop sees a genuine source group — never
        // the whole target group substituted in, which would corrupt row order.
        let draggedItems = groups.flatMap(\.flattenedItems).filter { payload.pageIDs.contains($0.id) }
        guard !draggedItems.isEmpty else { return false }
        let items = group.flattenedItems
        guard
            let context = buildDropContext(
                draggedItems, group, insertionIndex, anchorID(in: items, at: insertionIndex))
        else { return false }
        return dragCoordinator.drop(context: context)
    }

    /// The page id a drop at `index` within the group's flattened `items` lands
    /// BEFORE — the reorder anchor — or nil at the container end (append).
    private func anchorID(in items: [ViewItem], at index: Int) -> String? {
        items.indices.contains(index) ? items[index].id : nil
    }

    // MARK: - Live drop indicator

    /// Drive the insertion marker + group highlight off the drop session's
    /// LOCATION (not the nil-mid-flight payload), hit-tested in GRID FLOW ORDER
    /// against the captured card frames. `DropSession.location` is local to the
    /// firing card, so it's lifted to the shared GLOBAL space via that card's
    /// captured global frame — exactly the table's `updateDropFromLocation` seam,
    /// with `GalleryDropGeometry`'s horizontal-midpoint math in place of the
    /// table's vertical-midpoint math.
    private func updateDropFromLocation(
        _ session: DropSession, onto group: ResolvedGroup, elementFrame: CGRect?
    ) {
        switch session.phase {
        case .exiting, .ended, .dataTransferCompleted:
            dragCoordinator.update(nil)
            return
        default:
            break
        }
        guard let elementFrame else {
            dragCoordinator.update(nil)
            return
        }
        let location = CGPoint(
            x: elementFrame.minX + session.location.x,
            y: elementFrame.minY + session.location.y)

        let items = group.flattenedItems
        let draggedIDs = dragCoordinator.draggedIDs
        let cards = cardFrames(in: items)
        // Past the last CAPTURED card, append at the true container end — the card
        // frame registry only holds on-screen cards (LazyVGrid virtualization), so
        // the last captured index can sit mid-group when trailing cards scroll out.
        let index: Int
        if let last = cards.last, location.y >= last.frame.maxY {
            index = items.count
        } else {
            index =
                GalleryDropGeometry.insertionIndex(location: location, cards: cards)
                ?? items.count
        }
        // Resolve the dragged items across ALL groups (mirror of `handleDrop`), so
        // a cross-group hover sees the genuine source group and the planner shows a
        // move-highlight instead of an insertion line. An unresolvable drag clears.
        let dragged = groups.flatMap(\.flattenedItems).filter { draggedIDs.contains($0.id) }
        guard !dragged.isEmpty else {
            dragCoordinator.update(nil)
            return
        }
        dragCoordinator.update(
            buildDropContext(dragged, group, index, anchorID(in: items, at: index)))
    }

    /// The captured card frames for a group's flattened items, in flow order —
    /// feeds the pure grid-insertion math.
    private func cardFrames(in items: [ViewItem]) -> [GalleryDropGeometry.CardFrame] {
        items.enumerated().compactMap { idx, item in
            guard let frame = dragCoordinator.cardFrames[item.id] else { return nil }
            return GalleryDropGeometry.CardFrame(id: item.id, frame: frame, indexInGroup: idx)
        }
    }

    /// The vertical accent capsule drawn at the LEADING edge of the card the
    /// coordinator's insertion marker targets (insert-before).
    @ViewBuilder
    private func insertionCapsule(forItemID id: String, in group: ResolvedGroup) -> some View {
        if let marker = dragCoordinator.insertion,
            marker.groupID == group.id,
            let targeted = group.flattenedItems[safe: marker.index],
            targeted.id == id
        {
            dropCapsule
        }
    }

    /// The trailing-edge capsule for the APPEND case — when the insertion marker
    /// targets one past the last card, draw at the last card's trailing edge.
    @ViewBuilder
    private func appendCapsule(forItemID id: String, in group: ResolvedGroup) -> some View {
        let items = group.flattenedItems
        if let marker = dragCoordinator.insertion,
            marker.groupID == group.id,
            marker.index == items.count,
            items.last?.id == id
        {
            dropCapsule
        }
    }

    private var dropCapsule: some View {
        Capsule()
            .fill(.tint)
            .frame(width: 3)
            .padding(.vertical, PUI.Spacing.xs)
    }
}
