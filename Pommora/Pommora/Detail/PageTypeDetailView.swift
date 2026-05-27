import SwiftUI

struct PageTypeDetailView: View {
    let pageType: PageType
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var presentedItem: Item?  // drives Item Window popover
    @Binding var editingID: String?
    @Binding var justCreatedID: String?

    @State private var isCreatingPage: Bool = false
    @State private var isCreatingCollection: Bool = false

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(PageContentManager.self) private var contentManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var tableSelection: Set<String> = []
    @State private var expanded: Set<String> = []  // row IDs

    // Rename alert state (page or item).
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
        .task(id: pageType.id) {
            // Load Page-Type-root Pages + every PageCollection's content
            sessionOrder = nil
            await contentManager.loadAll(for: pageType)
            for coll in pageTypeManager.pageCollections(in: pageType) {
                await contentManager.loadAll(for: coll)
            }
        }
        .alert("Rename", isPresented: renameAlertBinding) {
            TextField("Title", text: $renameDraft)
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

    /// User-defined property columns derived from `pageType.views[0]` +
    /// schema. Empty when the active SavedView has no visibleProperties
    /// configured — collapses to the legacy Title/Kind/Modified shape.
    private var userPropertyColumns: [PropertyDefinition] {
        guard let view = pageType.views.first else { return [] }
        let cols = PropertyColumnBuilder.columns(view: view, schema: pageType.properties)
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
                    if case .page(let pageMeta) = row.kind {
                        let parentCollection = collectionContaining(pageID: pageMeta.id)
                        PropertyCellEditor(
                            definition: def,
                            value: pageMeta.frontmatter.properties[def.id],
                            relationResolver: { _ in nil },
                            commit: { newValue in
                                Task {
                                    try? await contentManager.updatePageProperty(
                                        pageMeta,
                                        propertyID: def.id,
                                        newValue: newValue,
                                        vault: pageType,
                                        collection: parentCollection
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

    /// Resolve the PropertyValue for a row + propertyID. Pages carry their
    /// frontmatter.properties; Collections + Items don't surface property
    /// values in this PageType view (Items are deferred per Phase 6).
    private func propertyValue(for row: DetailRow, propertyID: String) -> PropertyValue? {
        switch row.kind {
        case .page(let pageMeta):
            return pageMeta.frontmatter.properties[propertyID]
        case .collection, .item, .itemCollection:
            return nil
        }
    }

    /// Find the PageCollection (if any) that contains the page with the
    /// given ID. Returns nil for Page-Type-root pages (which is the correct
    /// `collection: nil` argument for updatePageProperty).
    private func collectionContaining(pageID: String) -> PageCollection? {
        for coll in pageTypeManager.pageCollections(in: pageType) {
            if contentManager.pages(in: coll).contains(where: { $0.id == pageID }) {
                return coll
            }
        }
        return nil
    }

    // MARK: - Drag-reorder (session-local, same-zone-only)

    private func zone(for row: DetailRow) -> DetailRowDragPayload.Zone {
        switch row.kind {
        case .collection: return .vaultCollection
        case .page, .item: return .vaultPage
        case .itemCollection: return .vaultPage  // unreachable in PageType context
        }
    }

    /// Drop handler — session-only. Same-zone only. Cross-zone drops
    /// (e.g. Page onto Collection) are silently rejected.
    @discardableResult
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

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                createPage()
            } label: {
                Label("New Page", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .disabled(isCreatingPage)

            Button {
                createCollection()
            } label: {
                Label("New Collection", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .disabled(isCreatingCollection)

            Spacer()
        }
        .padding(8)
    }

    /// Stub-and-edit "New Page" (at this PageType's root) trigger from the
    /// detail-view footer. Page lives at the PageType folder root (no
    /// PageCollection parent); the sidebar's PageTypeRow disclosure body
    /// includes Type-root Pages alongside Collections, and `editingID` flip
    /// lights up rename-mode on the newly-created row.
    private func createPage() {
        guard !isCreatingPage else { return }
        isCreatingPage = true
        let existing = contentManager.pages(in: pageType).map(\.title)
        let title = DefaultTitleResolver.resolve(label: "Page", existingTitles: existing)
        Task {
            defer { isCreatingPage = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await contentManager.createPage(name: title, inVaultRoot: pageType)
                    },
                    onCreate: { newPage in
                        editingID = newPage.id
                        justCreatedID = newPage.id
                    }
                )
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    /// Stub-and-edit "New Collection" trigger from the detail-view footer.
    private func createCollection() {
        guard !isCreatingCollection else { return }
        isCreatingCollection = true
        let label = settingsManager.settings.labels.pageCollection.singular
        let existing = pageTypeManager.pageCollections(in: pageType).map(\.title)
        let title = DefaultTitleResolver.resolve(label: label, existingTitles: existing)
        Task {
            defer { isCreatingCollection = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await pageTypeManager.createPageCollection(
                            name: title, inPageType: pageType
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
        let baseRows = rootRows + collectionRows
        guard let sessionOrder else { return baseRows }
        // Top-level session order override; child rows retain their natural order.
        let byID = Dictionary(uniqueKeysWithValues: baseRows.map { ($0.id, $0) })
        let ordered = sessionOrder.compactMap { byID[$0] }
        let known = Set(sessionOrder)
        let appended = baseRows.filter { !known.contains($0.id) }
        return ordered + appended
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
