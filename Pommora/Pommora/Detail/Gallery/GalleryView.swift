import SwiftUI

/// The Gallery renderer — parity sibling of `CustomTableView`. Consumes the
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
/// view's sort is manual). Selection is a self-contained `TableSelectionModel`
/// (page-id set), mirroring the table — sidebar selection is untouched.
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
            _ sourceIndices: IndexSet
        ) -> RowDragCoordinator.DropContext?

    @State private var collapsed: Set<String> = []
    @State private var selection = TableSelectionModel()

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
        .draggable(ViewRowDragPayload(pageIDs: dragIDs(for: item)))
        .dropDestination(for: ViewRowDragPayload.self) { payloads, _ in
            handleDrop(payloads, onto: group, at: offset)
        }
    }

    /// The drag payload's pages: the full selection when the dragged card is
    /// selected (parity with the table's multi-drag), else just this card.
    private func dragIDs(for item: ViewItem) -> [String] {
        if selection.selection.contains(item.id) { return Array(selection.selection) }
        return [item.id]
    }

    /// Route a card drop through the shared coordinator: build a DropContext at
    /// the target card's flattened index, then commit via `coordinator.drop`.
    private func handleDrop(_ payloads: [ViewRowDragPayload], onto group: ResolvedGroup, at insertionIndex: Int) -> Bool
    {
        guard let payload = payloads.first else { return false }
        let draggedItems = group.flattenedItems.filter { payload.pageIDs.contains($0.id) }
        let sourceIndices = IndexSet(
            group.flattenedItems.enumerated()
                .filter { payload.pageIDs.contains($0.element.id) }
                .map(\.offset))
        guard
            let context = buildDropContext(
                draggedItems.isEmpty ? group.flattenedItems : draggedItems,
                group, insertionIndex, sourceIndices)
        else { return false }
        return dragCoordinator.drop(payload: payload, context: context)
    }
}
