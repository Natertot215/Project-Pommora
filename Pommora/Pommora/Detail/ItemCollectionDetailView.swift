import SwiftUI

/// Pure-data composer for the Item Collection ("Set") detail table rows.
/// Items in a Set are flat — no nesting. Extracted from the view so unit
/// tests can verify composition without instantiating SwiftUI.
@MainActor
struct ItemCollectionDetailRowComposer {
    let collection: ItemCollection
    let itemContentManager: ItemContentManager

    func rows() -> [DetailRow] {
        itemContentManager.items(in: collection).map { item in
            DetailRow(
                id: item.id,
                title: item.title,
                kind: .item(item),
                iconName: item.icon ?? "doc",
                modifiedAt: item.modifiedAt,
                children: nil
            )
        }
    }
}

struct ItemCollectionDetailView: View {
    let collection: ItemCollection
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var presentedItem: Item?
    @Binding var editingID: String?
    @Binding var justCreatedID: String?

    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(ItemContentManager.self) private var itemContentManager
    @Environment(NexusManager.self) private var nexusManager
    @Environment(TierConfigManager.self) private var tierConfigManager
    @Environment(RelationDisplayResolver.self) private var relationDisplay

    @State private var renameTarget: DetailRow?
    @State private var renameDraft: String = ""
    @State private var isCreatingItem: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            table
            Divider()
            footer
        }
        .task(id: collection.id) {
            await itemContentManager.loadAll(for: collection)
        }
        .alert("Rename", isPresented: renameAlertBinding) {
            TextField("Title", text: $renameDraft)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            if let row = renameTarget {
                Text("Rename \(row.kindLabel.lowercased()) \"\(row.title)\"")
            }
        }
    }

    private var header: some View {
        HStack {
            Label {
                Text(collection.title)
            } icon: {
                Image(systemName: "folder")
            }
            .font(.title2.bold())
            Spacer()
        }
        .padding()
    }

    /// User-defined property columns derived from `collection.views[0]` +
    /// parent ItemType's schema. Empty when the SavedView has no
    /// visibleProperties — collapses to legacy Title/Modified shape.
    /// Live collection from the `@Observable` manager (by id) so view edits re-render
    /// immediately; the parent Type (schema source) is already a live manager lookup
    /// (`parentItemType`), so schema reactivity comes for free — this just makes the
    /// collection's own view source live too (the `collection` param is a stale snapshot).
    private var liveCollection: ItemCollection {
        guard let parent = itemTypeManager.parentItemType(for: collection) else { return collection }
        return itemTypeManager.itemCollections(in: parent).first { $0.id == collection.id } ?? collection
    }

    private var userPropertyColumns: [PropertyDefinition] {
        guard let view = liveCollection.views.first,
            let parent = itemTypeManager.parentItemType(for: collection)
        else { return [] }
        let cols = PropertyColumnBuilder.columns(
            view: view,
            schema: parent.resolvedProperties(tierConfig: tierConfigManager.config)
        )
        return cols.compactMap { col in
            if case .userProperty(let def) = col.kind { return def }
            return nil
        }
    }

    /// Relation + tier target IDs across every visible Item row — drives the
    /// resolver warm so cells render icon + title instead of "(missing)".
    private var visibleRelationIDs: [String] {
        let relationColumns = userPropertyColumns.filter { $0.type == .relation }
        return rows.flatMap { row -> [String] in
            guard case .item(let item) = row.kind else { return [] }
            let tiers = item.tier1 + item.tier2 + item.tier3
            let props = relationColumns.flatMap { item.relationIDs(forPropertyID: $0.id) }
            return tiers + props
        }
    }

    private var table: some View {
        Table(of: DetailRow.self) {
            TableColumn("Title") { row in
                Label {
                    Text(row.title)
                } icon: {
                    Image(systemName: row.iconName)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                // simultaneousGesture (not onTapGesture) so double-click-to-open
                // coexists with the row drag instead of blocking it near the title.
                .simultaneousGesture(TapGesture(count: 2).onEnded { handleDoubleTap(row) })
                .contextMenu { menuItems(for: row) }
            }
            TableColumnForEach(userPropertyColumns, id: \.id) { def in
                TableColumn(def.name) { row in
                    if case .item(let item) = row.kind,
                        let parent = itemTypeManager.parentItemType(for: collection)
                    {
                        PropertyCellEditor(
                            definition: def,
                            value: def.type == .relation
                                ? .relation(item.relationIDs(forPropertyID: def.id))
                                : item.properties[def.id],
                            relationResolver: { relationDisplay.resolve($0) },
                            commit: { newValue in
                                Task {
                                    try? await itemContentManager.updateItemProperty(
                                        item,
                                        propertyID: def.id,
                                        newValue: newValue,
                                        type: parent,
                                        collection: collection
                                    )
                                }
                            },
                            index: nexusManager.currentIndex
                        )
                    } else {
                        PropertyCellDisplay(
                            definition: def,
                            value: nil,
                            relationResolver: { relationDisplay.resolve($0) }
                        )
                    }
                }
                .width(min: 90, ideal: 120, max: 220)
            }
            TableColumn("Modified") { row in
                Text(row.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .width(min: 140, ideal: 180, max: 240)
        } rows: {
            // Row-level drag = reorder (the table-specialized API). Selection
            // highlight was removed so the drag owns the gesture; multi-select
            // returns as a hover checkbox in v0.4.0.
            ForEach(rows) { row in
                TableRow(row)
                    .draggable(DetailRowDragPayload(rowID: row.id))
            }
            .dropDestination(for: DetailRowDragPayload.self) { offset, payloads in
                handleDrop(payloads: payloads, toOffset: offset)
            }
        }
        .task(id: visibleRelationIDs) {
            await relationDisplay.warm(visibleRelationIDs)
        }
    }

    private func propertyValue(for row: DetailRow, propertyID: String) -> PropertyValue? {
        switch row.kind {
        case .item(let item):
            return item.properties[propertyID]
        case .page, .collection, .itemCollection:
            return nil
        }
    }

    // MARK: - Drag-reorder (persisted via manager)

    /// Row drop handler — persists via manager. `offset` is the insertion index
    /// the table's row `dropDestination` reports. Unknown payloads and no-ops
    /// are dropped by the planner.
    private func handleDrop(payloads: [DetailRowDragPayload], toOffset offset: Int) {
        guard let payload = payloads.first else { return }
        guard let plan = DetailReorderPlanner.plan(rows: rows, movingRowID: payload.rowID, dropOffset: offset) else { return }
        if plan.kind == .item {
            itemContentManager.reorderItems(in: collection, fromOffsets: plan.fromOffsets, toOffset: plan.toOffset)
        }
    }

    /// Stub-and-edit "New Item (in This Set)" trigger from the detail-view footer.
    private func createItem(parent: ItemType) {
        guard !isCreatingItem else { return }
        isCreatingItem = true
        let existing = itemContentManager.items(in: collection).map(\.title)
        let title = DefaultTitleResolver.resolve(label: "Item", existingTitles: existing)
        Task {
            defer { isCreatingItem = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await itemContentManager.createItem(
                            name: title, in: collection, type: parent
                        )
                    },
                    onCreate: { newItem in
                        editingID = newItem.id
                        justCreatedID = newItem.id
                    }
                )
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    private var footer: some View {
        // Parent must exist for + New Item — Sets are always inside a Type.
        // If parent isn't loaded yet, disable the button rather than ship a
        // bogus PlaceholderType into the sheet flow.
        let parent = itemTypeManager.parentItemType(for: collection)
        return HStack {
            Button {
                if let parent { createItem(parent: parent) }
            } label: {
                Label("New Item", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .disabled(parent == nil || isCreatingItem)
            Spacer()
        }
        .padding(8)
    }

    private var rows: [DetailRow] {
        ItemCollectionDetailRowComposer(
            collection: collection,
            itemContentManager: itemContentManager
        ).rows()
    }

    private func handleDoubleTap(_ row: DetailRow) {
        if case .item(let i) = row.kind {
            presentedItem = i
        }
    }

    @ViewBuilder
    private func menuItems(for row: DetailRow) -> some View {
        switch row.kind {
        case .item(let item):
            Button("Edit Title") { beginRename(row) }
            // Edit Icon needs the parent ItemType for container context; omit the
            // button if the parent isn't resolvable (rare race with parallel disk
            // mutations) rather than crash.
            if let parent = itemTypeManager.parentItemType(for: collection) {
                Button("Edit Icon") {
                    presentedSheet = .editIcon(.item(item, type: parent, collection: collection))
                }
            }
            Button(row.isPinned ? "Unpin Item" : "Pin Item") { row.togglePin() }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(row) }
            }
        case .page, .collection, .itemCollection:
            EmptyView()
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private func beginRename(_ row: DetailRow) {
        renameDraft = row.title
        renameTarget = row
    }

    private func commitRename() {
        guard let row = renameTarget else { return }
        let newName = renameDraft
        renameTarget = nil
        guard !newName.isEmpty, newName != row.title else { return }
        // Resolve parent for rename; if missing, no-op (rare race with parallel
        // disk mutations — toast surfaces via manager pendingError).
        guard let parent = itemTypeManager.parentItemType(for: collection) else { return }
        Task {
            do {
                if case .item(let i) = row.kind {
                    try await itemContentManager.renameItem(i, to: newName, in: collection, type: parent)
                }
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    private func delete(_ row: DetailRow) async {
        do {
            if case .item(let i) = row.kind {
                try await itemContentManager.deleteItem(i, in: collection)
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }
}
