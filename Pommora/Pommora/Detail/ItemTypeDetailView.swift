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
    @Binding var editingID: String?
    @Binding var justCreatedID: String?

    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(ItemContentManager.self) private var itemContentManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(NexusManager.self) private var nexusManager
    @Environment(TierConfigManager.self) private var tierConfigManager
    @Environment(ContextDisplayResolver.self) private var contextDisplay

    @State private var expanded: Set<String> = []  // set row IDs that are disclosed
    @State private var renameTarget: DetailRow?
    @State private var renameDraft: String = ""
    /// Container-delete confirmation target — set only from a Set row's menu.
    /// Item deletes stay direct (no confirmation); only the container case
    /// routes here, mirroring the sidebar's delete guard.
    @State private var deleteTarget: DetailRow?
    @State private var isCreatingItem: Bool = false
    @State private var isCreatingCollection: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            table
            Divider()
            footer
        }
        .task(id: type.id) {
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
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { row in
            Button("Delete", role: .destructive) {
                Task { await delete(row) }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { _ in
            Text("All Items inside will be deleted.")
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
    /// Live Type from the `@Observable` manager (by id) so schema/view edits (add /
    /// delete property, change-type) re-render the table IMMEDIATELY instead of only
    /// after a reselect — the `type` param is a value snapshot that goes stale on
    /// schema mutation. Mirrors `PageTypeDetailView.livePageType`.
    private var liveType: ItemType {
        itemTypeManager.types.first { $0.id == type.id } ?? type
    }

    private var userPropertyColumns: [PropertyDefinition] {
        guard let view = liveType.views.first else { return [] }
        let cols = PropertyColumnBuilder.columns(
            view: view,
            schema: liveType.resolvedProperties(tierConfig: tierConfigManager.config)
        )
        return cols.compactMap { col in
            if case .userProperty(let def) = col.kind { return def }
            return nil
        }
    }

    /// Relation + tier target IDs across every visible Item row — drives the
    /// resolver warm so cells render icon + title instead of "(missing)".
    private var visibleContextLinkIDs: [String] {
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
                // coexists with the row's built-in single-click selection.
                .simultaneousGesture(TapGesture(count: 2).onEnded { handleDoubleTap(row) })
                .contextMenu { menuItems(for: row) }
            }
            TableColumnForEach(userPropertyColumns, id: \.id) { def in
                TableColumn(def.name) { row in
                    if case .item(let item) = row.kind {
                        let parentSet = setContaining(itemID: item.id)
                        PropertyCellEditor(
                            definition: def,
                            value: def.type == .relation
                                ? .relation(item.relationIDs(forPropertyID: def.id))
                                : item.properties[def.id],
                            relationResolver: { contextDisplay.resolve($0) },
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
                            },
                            index: nexusManager.currentIndex
                        )
                    } else {
                        PropertyCellDisplay(
                            definition: def,
                            value: nil,
                            relationResolver: { contextDisplay.resolve($0) }
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
            // Display-only ordering (interim) — mirror of PageTypeDetailView.
            // Vault/type tables mirror the sidebar's file-level order; vault-level reorder is
            // deferred to the per-view system. Set (collection) tables keep their own reorder.
            // See Planning/2026-05-31-vault-table-displayonly-interim.md.
            ForEach(rows) { row in
                if let kids = row.children, !kids.isEmpty {
                    DisclosureTableRow(row, isExpanded: expandedBinding(for: row.id)) {
                        ForEach(kids) { kid in
                            TableRow(kid)
                        }
                    }
                } else {
                    TableRow(row)
                }
            }
        }
        .task(id: visibleContextLinkIDs) {
            await contextDisplay.warm(visibleContextLinkIDs)
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

    /// Stable per-row disclosure binding so a Set's expanded state survives the
    /// frequent `rows` recomputes (every manager change).
    private func expandedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOn in
                if isOn { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    private var footer: some View {
        let setLabel = settingsManager.settings.labels.itemCollection.singular
        let crumbs: [FooterCrumb] = [FooterCrumb(title: type.title)]
        return DetailFooterBar(crumbs: crumbs) {
            FooterAddMenuButton(
                items: [
                    .init(label: "New Item", isDisabled: isCreatingItem, action: createItem),
                    .init(label: "New \(setLabel)", isDisabled: isCreatingCollection, action: createItemCollection),
                ],
                allDisabled: isCreatingItem && isCreatingCollection
            )
        }
    }

    /// Stub-and-edit "New Item" (at ItemType root) from the detail-view footer.
    private func createItem() {
        guard !isCreatingItem else { return }
        isCreatingItem = true
        let existing = itemContentManager.items(in: type).map(\.title)
        let title = DefaultTitleResolver.resolve(label: "Item", existingTitles: existing)
        Task {
            defer { isCreatingItem = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await itemContentManager.createItem(name: title, inTypeRoot: type)
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

    /// Stub-and-edit "New Set" (ItemCollection) from the detail-view footer.
    private func createItemCollection() {
        guard !isCreatingCollection else { return }
        isCreatingCollection = true
        let label = settingsManager.settings.labels.itemCollection.singular
        let existing = itemTypeManager.itemCollections(in: type).map(\.title)
        let title = DefaultTitleResolver.resolve(label: label, existingTitles: existing)
        Task {
            defer { isCreatingCollection = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await itemTypeManager.createItemCollection(
                            name: title, inItemType: type
                        )
                    },
                    onCreate: { newCollection in
                        editingID = newCollection.id
                        justCreatedID = newCollection.id
                    }
                )
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    private var rows: [DetailRow] {
        ItemTypeDetailRowComposer(
            type: type,
            itemTypeManager: itemTypeManager,
            itemContentManager: itemContentManager
        ).rows()
    }

    private func handleDoubleTap(_ row: DetailRow) {
        switch row.kind {
        case .item(let i): AppGlobals.presentItemAction?(i)
        case .itemCollection(let c): selection = .itemCollection(c)
        case .page, .collection: break
        }
    }

    @ViewBuilder
    private func menuItems(for row: DetailRow) -> some View {
        switch row.kind {
        case .item(let item):
            Button("Edit Title") { beginRename(row) }
            Button("Edit Icon") {
                presentedSheet = .editIcon(.item(item, type: type, collection: nil))
            }
            Button(row.isPinned ? "Unpin Item" : "Pin Item") { row.togglePin() }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(row) }
            }
        case .itemCollection(let set):
            Button("Open") { handleDoubleTap(row) }
            Button("Edit Title") { beginRename(row) }
            Button("Edit Icon") {
                presentedSheet = .editIcon(.itemCollection(set))
            }
            Divider()
            // Container delete is guarded — route through the confirmation
            // dialog (mirrors the sidebar). Item deletes stay direct.
            Button("Delete", role: .destructive) {
                deleteTarget = row
            }
        case .page, .collection:
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

    /// Title for the container-delete confirmation. Mirrors the sidebar's
    /// `confirmationTitle` — uses the configured Set label.
    private var deleteConfirmationTitle: String {
        guard let row = deleteTarget else { return "" }
        let label = settingsManager.settings.labels.itemCollection.singular
        return "Delete \(label) \"\(row.title)\"?"
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
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
