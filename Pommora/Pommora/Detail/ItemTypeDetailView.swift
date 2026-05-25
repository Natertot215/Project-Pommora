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
            TextField("Name", text: $renameDraft)
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

    private var table: some View {
        Table(rows, children: \.children, selection: $tableSelection) {
            TableColumn("Name") { row in
                Label {
                    Text(row.title)
                } icon: {
                    Image(systemName: row.iconName)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { handleDoubleTap(row) }
                .contextMenu { menuItems(for: row) }
            }
            TableColumn("Modified") { row in
                Text(row.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .width(min: 140, ideal: 180, max: 240)
        }
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
        ItemTypeDetailRowComposer(
            type: type,
            itemTypeManager: itemTypeManager,
            itemContentManager: itemContentManager
        ).rows()
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
