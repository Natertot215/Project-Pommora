import SwiftUI

struct PageTypeDetailView: View {
    let pageType: PageType
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var presentedItem: Item?  // drives Item Window popover

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(PageContentManager.self) private var contentManager

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
        .task(id: pageType.id) {
            // Load Page-Type-root Pages + every PageCollection's content
            await contentManager.loadAll(for: pageType)
            for coll in pageTypeManager.pageCollections(in: pageType) {
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
                Text(pageType.title)
            } icon: {
                Image(systemName: pageType.icon ?? "tray.2")
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
                presentedSheet = .newPageInPageType(pageType: pageType)
            } label: {
                Label("New Page", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)

            Button {
                presentedSheet = .newCollection(pageType: pageType)
            } label: {
                Label("New Collection", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)

            Spacer()
        }
        .padding(8)
    }

    // MARK: - Row construction

    private var rows: [DetailRow] {
        // Page-Type-root Pages appear as top-level rows alongside Collections.
        //
        // ParadigmV2 (Task 5.5): Items have moved to ItemContentManager keyed on
        // ItemType/ItemCollection. PageType-side Items disappear from this surface
        // until Phase 6 lands the wrapper-folder layout + ItemTypeManager wiring,
        // at which point an Items-side detail surface ships in parallel.
        let rootPages = contentManager.pages(in: pageType).map(ContentItem.page)
        let rootItems: [ContentItem] = []  // TODO Phase 6: surface ItemType-root Items
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
        let collectionRows: [DetailRow] = pageTypeManager.pageCollections(in: pageType).map { coll in
            let pages = contentManager.pages(in: coll).map(ContentItem.page)
            let items: [ContentItem] = []  // TODO Phase 6: surface ItemCollection Items
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
        case .itemCollection:
            break  // never appears in PageTypeDetailView context
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
        case .collection, .itemCollection:
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
        case .collection, .itemCollection: return nil
        }
        // Page-Type-root first.
        switch row.kind {
        case .page:
            if contentManager.pages(in: pageType).contains(where: { $0.id == id }) {
                return .vaultRoot(pageType)
            }
        case .item:
            // TODO Phase 6: route through ItemContentManager + ItemTypeManager.
            return nil
        case .collection, .itemCollection:
            return nil
        }
        // Then every collection.
        for coll in pageTypeManager.pageCollections(in: pageType) {
            switch row.kind {
            case .page:
                if contentManager.pages(in: coll).contains(where: { $0.id == id }) {
                    return .collection(coll, vault: pageType)
                }
            case .item:
                // TODO Phase 6: ItemCollection route.
                return nil
            case .collection, .itemCollection:
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
        case .collection, .itemCollection: return nil
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
                    case .collection(let coll, let t):
                        try await contentManager.renamePage(p, to: newName, in: coll, vault: t)
                    case .vaultRoot(let t):
                        try await contentManager.renamePage(p, to: newName, inVaultRoot: t)
                    }
                case .item:
                    // TODO Phase 6: route through ItemContentManager.renameItem
                    // (parent lookup for Items returns nil during Phase 5, so
                    // this branch is currently unreachable).
                    break
                case .collection, .itemCollection:
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
                case .vaultRoot(let t):
                    try await contentManager.deletePage(p, inVaultRoot: t)
                }
            case .item:
                // TODO Phase 6: route through ItemContentManager.deleteItem.
                break
            case .collection, .itemCollection:
                break
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }
}
