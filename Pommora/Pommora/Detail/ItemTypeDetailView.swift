import SwiftUI

/// Pure-data composer for the Item Type detail table rows. Extracted from
/// the view so unit tests can verify row order without instantiating
/// SwiftUI. Mirrors the PageTypeDetailView row-composition logic with
/// two divergences: (1) Sets come BEFORE root Items (Nathan's directive
/// 2026-05-25); (2) no Kind column (UI label divergence — Items-side is
/// homogeneous so the column is redundant).
@MainActor
struct ItemTypeDetailRowComposer {
    let type: ItemType
    let itemTypeManager: ItemTypeManager
    let itemContentManager: ItemContentManager

    func rows() -> [DetailRow] {
        let setRows: [DetailRow] = itemTypeManager.itemCollections(in: type).map { set in
            let kids: [DetailRow] = itemContentManager.items(in: set).map { item in
                DetailRow(
                    id: item.id,
                    title: item.title,
                    kind: .item(item),
                    iconName: item.icon ?? "doc",
                    modifiedAt: item.modifiedAt,
                    children: nil
                )
            }
            return DetailRow(
                id: "set-\(set.id)",
                title: set.title,
                kind: .itemCollection(set),
                iconName: "folder",
                modifiedAt: set.modifiedAt,
                children: kids
            )
        }
        let rootItemRows: [DetailRow] = itemContentManager.items(in: type).map { item in
            DetailRow(
                id: item.id,
                title: item.title,
                kind: .item(item),
                iconName: item.icon ?? "doc",
                modifiedAt: item.modifiedAt,
                children: nil
            )
        }
        return setRows + rootItemRows
    }
}

struct ItemTypeDetailView: View {
    let type: ItemType
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var presentedItem: Item?

    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(ItemContentManager.self) private var itemContentManager
    @Environment(SettingsManager.self) private var settingsManager

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
        .task(id: type.id) {
            sessionOrder = nil
            await itemContentManager.loadAll(for: type)
            for set in itemTypeManager.itemCollections(in: type) {
                await itemContentManager.loadAll(for: set)
            }
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
                Text(type.title)
            } icon: {
                Image(systemName: type.icon ?? "tray.full")
            }
            .font(.title2.bold())
            Spacer()
        }
        .padding()
    }

    /// User-defined property columns derived from `type.views[0]` +
    /// type schema. Empty when the SavedView has no visibleProperties —
    /// collapses to the legacy Title/Modified shape.
    private var userPropertyColumns: [PropertyDefinition] {
        guard let view = type.views.first else { return [] }
        let cols = PropertyColumnBuilder.columns(view: view, schema: type.properties)
        return cols.compactMap { col in
            if case .userProperty(let def) = col.kind { return def }
            return nil
        }
    }

    private var table: some View {
        Table(rows, children: \.children, selection: $tableSelection) {
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
                .draggable(DetailRowDragPayload(rowID: row.id, zone: zone(for: row)))
                .dropDestination(for: DetailRowDragPayload.self) { payloads, _ in
                    handleDrop(payloads: payloads, ontoRowID: row.id)
                }
            }
            TableColumnForEach(userPropertyColumns, id: \.id) { def in
                TableColumn(def.name) { row in
                    if case .item(let item) = row.kind {
                        let parentSet = setContaining(itemID: item.id)
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
                                        type: type,
                                        collection: parentSet
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
        case .itemCollection, .page, .collection:
            return nil
        }
    }

    /// Find the ItemCollection (Set) (if any) that contains the item with
    /// the given ID. Returns nil for ItemType-root items (which is the
    /// correct `collection: nil` argument for updateItemProperty).
    private func setContaining(itemID: String) -> ItemCollection? {
        for set in itemTypeManager.itemCollections(in: type) {
            if itemContentManager.items(in: set).contains(where: { $0.id == itemID }) {
                return set
            }
        }
        return nil
    }

    // MARK: - Drag-reorder (session-local, same-zone-only)

    private func zone(for row: DetailRow) -> DetailRowDragPayload.Zone {
        switch row.kind {
        case .itemCollection: return .typeSet
        case .item: return .typeRootItem
        case .page, .collection: return .typeRootItem  // unreachable in ItemType context
        }
    }

    /// Drop handler — session-only. Same-zone only. Cross-zone drops
    /// (e.g. Item onto Set or vice versa) are silently rejected.
    private func handleDrop(payloads: [DetailRowDragPayload], ontoRowID targetID: String) -> Bool {
        guard let payload = payloads.first else { return false }
        let currentRows = rows
        guard let targetRow = currentRows.first(where: { $0.id == targetID }) else { return false }
        guard payload.zone == zone(for: targetRow) else { return false }

        let currentIDs = currentRows.map(\.id)
        let next = SessionRowOrdering.apply(base: currentIDs, movingID: payload.rowID, ontoID: targetID)
        guard next != currentIDs else { return false }
        sessionOrder = next
        return true
    }

    private var footer: some View {
        let setLabel = settingsManager.settings.labels.itemCollection.singular
        return HStack {
            Button {
                presentedSheet = .newItem(collection: nil, type: type)
            } label: {
                Label("New Item", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)

            Button {
                presentedSheet = .newItemCollection(type: type)
            } label: {
                Label("New \(setLabel)", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)

            Spacer()
        }
        .padding(8)
    }

    private var rows: [DetailRow] {
        let baseRows = ItemTypeDetailRowComposer(
            type: type,
            itemTypeManager: itemTypeManager,
            itemContentManager: itemContentManager
        ).rows()
        guard let sessionOrder else { return baseRows }
        // Top-level session order override; child rows retain their natural order.
        let byID = Dictionary(uniqueKeysWithValues: baseRows.map { ($0.id, $0) })
        let ordered = sessionOrder.compactMap { byID[$0] }
        let known = Set(sessionOrder)
        let appended = baseRows.filter { !known.contains($0.id) }
        return ordered + appended
    }

    private func handleDoubleTap(_ row: DetailRow) {
        switch row.kind {
        case .item(let i): presentedItem = i
        case .itemCollection(let c): selection = .itemCollection(c)
        case .page, .collection: break
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
        case .itemCollection:
            Button("Open") { handleDoubleTap(row) }
            Button("Rename") { beginRename(row) }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(row) }
            }
        case .page, .collection:
            EmptyView()
        }
    }

    private func stateRef(for row: DetailRow) -> EntityStateRef? {
        switch row.kind {
        case .item(let i): return EntityStateRef(kind: .item, id: i.id, title: i.title)
        case .itemCollection, .page, .collection: return nil
        }
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
        Task {
            do {
                switch row.kind {
                case .item(let i):
                    if let parent = findItemParent(itemID: i.id) {
                        switch parent {
                        case .collection(let c):
                            try await itemContentManager.renameItem(i, to: newName, in: c, type: type)
                        case .typeRoot:
                            try await itemContentManager.renameItem(i, to: newName, inTypeRoot: type)
                        }
                    }
                case .itemCollection(let c):
                    try await itemTypeManager.renameItemCollection(c, to: newName)
                case .page, .collection:
                    break
                }
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    private func delete(_ row: DetailRow) async {
        do {
            switch row.kind {
            case .item(let i):
                if let parent = findItemParent(itemID: i.id) {
                    switch parent {
                    case .collection(let c):
                        try await itemContentManager.deleteItem(i, in: c)
                    case .typeRoot:
                        try await itemContentManager.deleteItem(i, inTypeRoot: type)
                    }
                }
            case .itemCollection(let c):
                try await itemTypeManager.deleteItemCollection(c)
            case .page, .collection:
                break
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }

    private enum ItemParent {
        case collection(ItemCollection)
        case typeRoot
    }

    private func findItemParent(itemID: String) -> ItemParent? {
        if itemContentManager.items(in: type).contains(where: { $0.id == itemID }) {
            return .typeRoot
        }
        for set in itemTypeManager.itemCollections(in: type)
        where itemContentManager.items(in: set).contains(where: { $0.id == itemID }) {
            return .collection(set)
        }
        return nil
    }
}
