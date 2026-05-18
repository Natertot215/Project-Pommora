import SwiftUI

struct CollectionDetailView: View {
    let collection: Pommora.Collection
    let vault: Vault
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var presentedItem: Item?

    @Environment(ContentManager.self) private var contentManager

    @State private var tableSelection: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            table
            Divider()
            footer
        }
        .task(id: collection.id) {
            await contentManager.loadAll(for: collection)
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

    private func handleDoubleTap(_ row: DetailRow) {
        switch row.kind {
        case .item(let i): presentedItem = i
        case .page(let p): selection = .page(p)
        case .collection: break
        }
    }

    private var footer: some View {
        HStack {
            Button {
                presentedSheet = .newPage(collection: collection, vault: vault)
            } label: {
                Label("New Page", systemImage: "plus")
            }
            .buttonStyle(.borderless)

            Button {
                presentedSheet = .newItem(collection: collection, vault: vault)
            } label: {
                Label("New Item", systemImage: "plus")
            }
            .buttonStyle(.borderless)

            Spacer()
        }
        .padding(8)
    }

    private var rows: [DetailRow] {
        let pages = contentManager.pages(in: collection).map { ContentItem.page($0) }
        let items = contentManager.items(in: collection).map { ContentItem.item($0) }
        return (pages + items).map { ci in
            DetailRow(
                id: ci.id,
                title: ci.title,
                kind: detailKind(ci),
                iconName: ci.iconName,
                modifiedAt: ci.modifiedAt,
                children: nil  // v1 Collections are flat; nil = leaf row (no disclosure)
            )
        }
    }

    private func detailKind(_ ci: ContentItem) -> DetailRow.Kind {
        switch ci {
        case .page(let p): return .page(p)
        case .item(let i): return .item(i)
        }
    }
}
