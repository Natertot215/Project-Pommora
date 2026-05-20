import SwiftUI

struct VaultDetailView: View {
    let vault: Vault
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var presentedItem: Item?  // drives Item Window popover

    @Environment(VaultManager.self) private var vaultManager
    @Environment(ContentManager.self) private var contentManager

    @State private var tableSelection: Set<String> = []
    @State private var expanded: Set<String> = []  // row IDs

    // Rename alert state (page or item).
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
        .task(id: vault.id) {
            // Load vault-root Pages/Items + every Collection's content
            await contentManager.loadAll(for: vault)
            for coll in vaultManager.collections(in: vault) {
                await contentManager.loadAll(for: coll)
            }
        }
        .alert("Rename", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameDraft)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            if let row = renameTarget {
                Text("Rename \(row.kindLabel.lowercased()) “\(row.title)”")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label {
                Text(vault.title)
            } icon: {
                Image(systemName: vault.icon ?? "tray.2")
            }
            .font(.title2.bold())
            Spacer()
        }
        .padding()
    }

    // MARK: - Table

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
            TableColumn("Kind") { row in
                Text(row.kindLabel).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100, max: 140)
            TableColumn("Modified") { row in
                Text(row.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .width(min: 140, ideal: 180, max: 240)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                presentedSheet = .newCollection(vault: vault)
            } label: {
                Label("New Collection", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .padding(8)
    }

    // MARK: - Row construction

    private var rows: [DetailRow] {
        // Vault-root Pages and Items appear as top-level rows alongside Collections.
        let rootPages = contentManager.pages(in: vault).map(ContentItem.page)
        let rootItems = contentManager.items(in: vault).map(ContentItem.item)
        let rootRows: [DetailRow] = (rootPages + rootItems).map { ci in
            DetailRow(
                id: ci.id,
                title: ci.title,
                kind: contentKind(ci),
                iconName: ci.iconName,
                modifiedAt: ci.modifiedAt,
                children: nil
            )
        }
        let collectionRows: [DetailRow] = vaultManager.collections(in: vault).map { coll in
            let pages = contentManager.pages(in: coll).map(ContentItem.page)
            let items = contentManager.items(in: coll).map(ContentItem.item)
            let kids: [DetailRow] = (pages + items).map { ci in
                DetailRow(
                    id: ci.id,
                    title: ci.title,
                    kind: contentKind(ci),
                    iconName: ci.iconName,
                    modifiedAt: ci.modifiedAt,
                    children: nil
                )
            }
            return DetailRow(
                id: "collection-\(coll.id)",
                title: coll.title,
                kind: .collection(coll),
                iconName: "folder",
                modifiedAt: coll.modifiedAt,
                children: kids
            )
        }
        return rootRows + collectionRows
    }

    private func contentKind(_ ci: ContentItem) -> DetailRow.Kind {
        switch ci {
        case .page(let p): return .page(p)
        case .item(let i): return .item(i)
        }
    }

    // MARK: - Interaction

    private func handleDoubleTap(_ row: DetailRow) {
        switch row.kind {
        case .collection(let c):
            selection = .collection(c)
        case .item(let i):
            presentedItem = i
        case .page(let p):
            selection = .page(p)
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func menuItems(for row: DetailRow) -> some View {
        switch row.kind {
        case .page, .item:
            Button("Rename") { beginRename(row) }
            Button(isPinned(row) ? "Unpin \(row.kindLabel)" : "Pin \(row.kindLabel)") {
                togglePin(row)
            }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(row) }
            }
        case .collection:
            EmptyView()
        }
    }

    // MARK: - Parent lookup
    //
    // O(collections × content) — fine for v0.2.7.2.1; SQLite in v0.4.0 makes
    // this O(1). Called only on context-menu actions, not in render.

    private func parent(for row: DetailRow) -> PageParent? {
        let id: String
        switch row.kind {
        case .page(let p): id = p.id
        case .item(let i): id = i.id
        case .collection: return nil
        }
        // Vault-root first.
        switch row.kind {
        case .page:
            if contentManager.pages(in: vault).contains(where: { $0.id == id }) {
                return .vaultRoot(vault)
            }
        case .item:
            if contentManager.items(in: vault).contains(where: { $0.id == id }) {
                return .vaultRoot(vault)
            }
        case .collection:
            return nil
        }
        // Then every collection.
        for coll in vaultManager.collections(in: vault) {
            switch row.kind {
            case .page:
                if contentManager.pages(in: coll).contains(where: { $0.id == id }) {
                    return .collection(coll, vault: vault)
                }
            case .item:
                if contentManager.items(in: coll).contains(where: { $0.id == id }) {
                    return .collection(coll, vault: vault)
                }
            case .collection:
                return nil
            }
        }
        return nil
    }

    // MARK: - Pin

    private func stateRef(for row: DetailRow) -> EntityStateRef? {
        switch row.kind {
        case .page(let p): return EntityStateRef(kind: .page, id: p.id, title: p.title)
        case .item(let i): return EntityStateRef(kind: .item, id: i.id, title: i.title)
        case .collection: return nil
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

    // MARK: - Rename

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
        guard let parent = parent(for: row) else { return }
        Task {
            do {
                switch row.kind {
                case .page(let p):
                    switch parent {
                    case .collection(let coll, let vault):
                        try await contentManager.renamePage(p, to: newName, in: coll, vault: vault)
                    case .vaultRoot(let vault):
                        try await contentManager.renamePage(p, to: newName, inVaultRoot: vault)
                    }
                case .item(let i):
                    switch parent {
                    case .collection(let coll, let vault):
                        try await contentManager.renameItem(i, to: newName, in: coll, vault: vault)
                    case .vaultRoot(let vault):
                        try await contentManager.renameItem(i, to: newName, inVaultRoot: vault)
                    }
                case .collection:
                    break
                }
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    // MARK: - Delete

    private func delete(_ row: DetailRow) async {
        guard let parent = parent(for: row) else { return }
        do {
            switch row.kind {
            case .page(let p):
                switch parent {
                case .collection(let coll, _):
                    try await contentManager.deletePage(p, in: coll)
                case .vaultRoot(let vault):
                    try await contentManager.deletePage(p, inVaultRoot: vault)
                }
            case .item(let i):
                switch parent {
                case .collection(let coll, _):
                    try await contentManager.deleteItem(i, in: coll)
                case .vaultRoot(let vault):
                    try await contentManager.deleteItem(i, inVaultRoot: vault)
                }
            case .collection:
                break
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }
}
