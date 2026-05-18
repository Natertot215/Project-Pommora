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

    private func findRow(id: String, in rows: [DetailRow]) -> DetailRow? {
        for row in rows {
            if row.id == id { return row }
            if let kids = row.children, let hit = findRow(id: id, in: kids) {
                return hit
            }
        }
        return nil
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
}
