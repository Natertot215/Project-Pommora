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

    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(ItemContentManager.self) private var itemContentManager

    @State private var tableSelection: Set<String> = []
    @State private var renameTarget: DetailRow?
    @State private var renameDraft: String = ""
    /// Session-local row order override. Nil → fall back to manager order.
    /// Resets on entity change. Independent of the sidebar's reorder system.
    @State private var sessionOrder: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            table
            Divider()
            footer
        }
        .task(id: collection.id) {
            sessionOrder = nil
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
        let parent = itemTypeManager.parentItemType(for: collection)
        return HStack(spacing: 6) {
            if let parent {
                Button {
                    selection = .itemType(parent)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.footnote)
                        Text(parent.title)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Text("›").foregroundStyle(.tertiary)
            }
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
    private var userPropertyColumns: [PropertyDefinition] {
        guard let view = collection.views.first,
              let parent = itemTypeManager.parentItemType(for: collection)
        else { return [] }
        let cols = PropertyColumnBuilder.columns(view: view, schema: parent.properties)
        return cols.compactMap { col in
            if case .userProperty(let def) = col.kind { return def }
            return nil
        }
    }

    private var table: some View {
        Table(rows, selection: $tableSelection) {
            TableColumn("Title") { row in
                Label {
                    Text(row.title)
                } icon: {
                    Image(systemName: row.iconName)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { handleDoubleTap(row) }
                .contextMenu { menuItems(for: row) }
                .draggable(DetailRowDragPayload(rowID: row.id, zone: .setItem))
                .dropDestination(for: DetailRowDragPayload.self) { payloads, _ in
                    handleDrop(payloads: payloads, ontoRowID: row.id)
                }
            }
            TableColumnForEach(userPropertyColumns, id: \.id) { def in
                TableColumn(def.name) { row in
                    if case .item(let item) = row.kind,
                       let parent = itemTypeManager.parentItemType(for: collection)
                    {
                        PropertyCellEditor(
                            definition: def,
                            value: item.properties[def.id],
                            relationResolver: { _ in nil },
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
                            }
                        )
                    } else {
                        PropertyCellDisplay(
                            definition: def,
                            value: nil,
                            relationResolver: { _ in nil }
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

    // MARK: - Drag-reorder (session-local, single-zone)

    /// Drop handler — session-only. Accepts `.setItem` or `.collectionItem`
    /// (synonyms in the v1 paradigm). Updates `sessionOrder`, which the
    /// `rows` computed honors. Never calls a manager API.
    private func handleDrop(payloads: [DetailRowDragPayload], ontoRowID targetID: String) -> Bool {
        guard let payload = payloads.first else { return false }
        guard payload.zone == .setItem || payload.zone == .collectionItem else { return false }
        let currentIDs = rows.map(\.id)
        let next = SessionRowOrdering.apply(base: currentIDs, movingID: payload.rowID, ontoID: targetID)
        guard next != currentIDs else { return false }
        sessionOrder = next
        return true
    }

    private var footer: some View {
        // Parent must exist for + New Item — Sets are always inside a Type.
        // If parent isn't loaded yet, disable the button rather than ship a
        // bogus PlaceholderType into the sheet flow.
        let parent = itemTypeManager.parentItemType(for: collection)
        return HStack {
            Button {
                if let parent {
                    presentedSheet = .newItem(collection: collection, type: parent)
                }
            } label: {
                Label("New Item", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .disabled(parent == nil)
            Spacer()
        }
        .padding(8)
    }

    private var rows: [DetailRow] {
        let baseRows = ItemCollectionDetailRowComposer(
            collection: collection,
            itemContentManager: itemContentManager
        ).rows()
        guard let sessionOrder else { return baseRows }
        let byID = Dictionary(uniqueKeysWithValues: baseRows.map { ($0.id, $0) })
        // Honor session order for known rows; append any newly added rows at the end.
        let ordered = sessionOrder.compactMap { byID[$0] }
        let known = Set(sessionOrder)
        let appended = baseRows.filter { !known.contains($0.id) }
        return ordered + appended
    }

    private func handleDoubleTap(_ row: DetailRow) {
        if case .item(let i) = row.kind {
            presentedItem = i
        }
    }

    @ViewBuilder
    private func menuItems(for row: DetailRow) -> some View {
        switch row.kind {
        case .item:
            Button("Rename") { beginRename(row) }
            Button(isPinned(row) ? "Unpin Item" : "Pin Item") { togglePin(row) }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(row) }
            }
        case .page, .collection, .itemCollection:
            EmptyView()
        }
    }

    private func stateRef(for row: DetailRow) -> EntityStateRef? {
        if case .item(let i) = row.kind {
            return EntityStateRef(kind: .item, id: i.id, title: i.title)
        }
        return nil
    }

    private func isPinned(_ row: DetailRow) -> Bool {
        guard let ref = stateRef(for: row) else { return false }
        return AppGlobals.pinnedManager?.contains(ref) ?? false
    }

    private func togglePin(_ row: DetailRow) {
        guard let ref = stateRef(for: row) else { return }
        AppGlobals.pinnedManager?.toggle(ref)
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
