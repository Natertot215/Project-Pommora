import SwiftUI

struct PageTypeDetailView: View {
    let pageType: PageType
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    /// Last page visited before navigating back to this vault; shown as a
    /// ghost trail crumb if the page lives at this vault's root.
    var trailPage: PageMeta? = nil

    @State private var isCreatingPage: Bool = false
    @State private var isCreatingCollection: Bool = false

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(PageContentManager.self) private var contentManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(NexusManager.self) private var nexusManager
    @Environment(TierConfigManager.self) private var tierConfigManager
    @Environment(RelationDisplayResolver.self) private var relationDisplay

    @State private var expanded: Set<String> = []  // collection row IDs that are disclosed

    // Rename alert state (page or item).
    @State private var renameTarget: DetailRow?
    @State private var renameDraft: String = ""
    /// Container-delete confirmation target — set only from a Collection row's
    /// menu. Page deletes stay direct (no confirmation); only the container
    /// case routes here, mirroring the sidebar's delete guard.
    @State private var deleteTarget: DetailRow?

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
            TextField("Title", text: $renameDraft)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            if let row = renameTarget {
                Text("Rename \(row.kindLabel.lowercased()) “\(row.title)”")
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
            Text("All Pages and Items inside will be deleted.")
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

    /// The live Type from the `@Observable` manager (by id), so schema/view edits
    /// (add / delete property, change-type) re-render this table IMMEDIATELY instead
    /// of only after a reselect. The `pageType` init param is a value snapshot taken
    /// at selection time and goes stale on schema mutation; reading the manager keeps
    /// this view reactive. Falls back to the snapshot if the manager hasn't loaded it.
    private var livePageType: PageType {
        pageTypeManager.types.first { $0.id == pageType.id } ?? pageType
    }

    /// User-defined property columns derived from `livePageType.views[0]` +
    /// schema. Empty when the active SavedView has no visibleProperties
    /// configured — collapses to the legacy Title/Kind/Modified shape.
    private var userPropertyColumns: [PropertyDefinition] {
        guard let view = livePageType.views.first else { return [] }
        let cols = PropertyColumnBuilder.columns(
            view: view,
            schema: livePageType.resolvedProperties(tierConfig: tierConfigManager.config)
        )
        return cols.compactMap { col in
            if case .userProperty(let def) = col.kind { return def }
            return nil
        }
    }

    /// Relation + tier target IDs across every visible Page row — drives the
    /// resolver warm so cells render icon + title instead of "(missing)".
    private var visibleRelationIDs: [String] {
        let relationColumns = userPropertyColumns.filter { $0.type == .relation }
        return rows.flatMap { row -> [String] in
            guard case .page(let pageMeta) = row.kind else { return [] }
            let fm = pageMeta.frontmatter
            let tiers = fm.tier1 + fm.tier2 + fm.tier3
            let props = relationColumns.flatMap { fm.relationIDs(forPropertyID: $0.id) }
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
                    if case .page(let pageMeta) = row.kind {
                        let parentCollection = collectionContaining(pageID: pageMeta.id)
                        PropertyCellEditor(
                            definition: def,
                            value: def.type == .relation
                                ? .relation(pageMeta.frontmatter.relationIDs(forPropertyID: def.id))
                                : pageMeta.frontmatter.properties[def.id],
                            relationResolver: { relationDisplay.resolve($0) },
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
            // Display-only ordering (interim): vault-level reorder is deferred — vault
            // tables mirror the sidebar's file-level order via the shared managers.
            // Reorder lives in the sidebar (file-level) and in each collection's own view.
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
        .task(id: visibleRelationIDs) {
            await relationDisplay.warm(visibleRelationIDs)
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

    /// Stable per-row disclosure binding so a Collection's expanded state
    /// survives the frequent `rows` recomputes (every manager change).
    private func expandedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOn in
                if isOn { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    // MARK: - Footer

    private var footer: some View {
        let collectionLabel = settingsManager.settings.labels.pageCollection.singular
        var crumbs: [FooterCrumb] = [FooterCrumb(title: pageType.title)]
        if let trail = trailPage,
           contentManager.pages(in: pageType).contains(where: { $0.id == trail.id }) {
            crumbs.append(FooterCrumb(title: trail.title, isGhost: true) { selection = .page(trail) })
        }
        return DetailFooterBar(crumbs: crumbs) {
            FooterAddMenuButton(
                items: [
                    .init(label: "New Page", isDisabled: isCreatingPage, action: createPage),
                    .init(label: "New \(collectionLabel)", isDisabled: isCreatingCollection, action: createCollection),
                ],
                allDisabled: isCreatingPage && isCreatingCollection
            )
        }
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
            AppGlobals.presentItemAction?(i)
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
        case .page(let meta):
            Button("Edit Title") { beginRename(row) }
            Button("Edit Icon") {
                presentedSheet = .editIcon(.page(meta, vault: pageType, collection: nil))
            }
            Button(row.isPinned ? "Unpin \(row.kindLabel)" : "Pin \(row.kindLabel)") {
                row.togglePin()
            }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(row) }
            }
        case .item:
            // Items never appear in PageTypeDetailView context, but the kind is
            // part of the shared DetailRow enum — keep the existing affordances
            // without an Edit Icon (no Item-container context on this view).
            Button("Edit Title") { beginRename(row) }
            Button(row.isPinned ? "Unpin \(row.kindLabel)" : "Pin \(row.kindLabel)") {
                row.togglePin()
            }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(row) }
            }
        case .collection(let coll):
            // Mirrors ItemTypeDetailView's Set menu for cross-side parity.
            // No Pin: containers aren't pinnable from detail views today.
            Button("Open") { handleDoubleTap(row) }
            Button("Edit Title") { beginRename(row) }
            Button("Edit Icon") {
                presentedSheet = .editIcon(.pageCollection(coll))
            }
            Divider()
            // Container delete is guarded — route through the confirmation
            // dialog (mirrors the sidebar). Page deletes stay direct.
            Button("Delete", role: .destructive) {
                deleteTarget = row
            }
        case .itemCollection:
            EmptyView()  // never appears in PageTypeDetailView context
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
        Task {
            do {
                switch row.kind {
                case .collection(let c):
                    // Collections rename via the manager directly — no parent
                    // lookup needed (the manager resolves the on-disk folder).
                    try await pageTypeManager.renamePageCollection(c, to: newName)
                case .page(let p):
                    guard let parent = parent(for: row) else { return }
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
                case .itemCollection:
                    break
                }
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    // MARK: - Delete

    /// Title for the container-delete confirmation. Mirrors the sidebar's
    /// `confirmationTitle` — uses the configured Collection label.
    private var deleteConfirmationTitle: String {
        guard let row = deleteTarget else { return "" }
        let label = settingsManager.settings.labels.pageCollection.singular
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
            case .collection(let c):
                try await pageTypeManager.deletePageCollection(c)
            case .page(let p):
                guard let parent = parent(for: row) else { return }
                switch parent {
                case .collection(let coll, _):
                    try await contentManager.deletePage(p, in: coll)
                case .vaultRoot(let t):
                    try await contentManager.deletePage(p, inVaultRoot: t)
                }
            case .item:
                // TODO Phase 6: route through ItemContentManager.deleteItem.
                break
            case .itemCollection:
                break
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }
}
