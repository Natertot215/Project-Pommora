import SwiftUI

struct PageCollectionDetailView: View {
    let collection: PageCollection
    let vault: PageType
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    /// Last page visited before navigating back to this collection; shown as
    /// a ghost trail crumb if the page belongs to this collection.
    var trailPage: PageMeta? = nil

    @State private var isCreatingPage: Bool = false
    @State private var isCreatingSet: Bool = false

    @Environment(PageContentManager.self) private var contentManager
    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(PageSetManager.self) private var pageSetManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(NexusManager.self) private var nexusManager
    @Environment(TierConfigManager.self) private var tierConfigManager
    @Environment(ContextDisplayResolver.self) private var contextDisplay

    @State private var expanded: Set<String> = []  // set row IDs that are disclosed

    @State private var renameTarget: DetailRow?
    @State private var renameDraft: String = ""
    /// Container-delete confirmation target — set only from a Set row's menu.
    /// Page deletes stay direct; the Set case routes through the same
    /// two-mode dialog the sidebar uses (Set only vs. Set and Pages).
    @State private var deleteTarget: DetailRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            table
            Divider()
            footer
        }
        .task(id: collection.id) {
            // Root pages + every Set's pages — Set rows render in this table
            // above the root zone with their pages as disclosure children,
            // so their caches must be warm too.
            await contentManager.loadAll(for: collection)
            for set in pageSetManager.pageSets(in: collection) {
                await contentManager.loadAll(for: set)
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
            if case .set(let set) = row.kind {
                Button("Delete Set Only") {
                    Task {
                        do { try await pageSetManager.deletePageSet(set, mode: .setOnly) } catch
                        { /* pendingError set by manager; toast surfaces */  }
                        deleteTarget = nil
                    }
                }
                Button("Delete Set and Pages", role: .destructive) {
                    Task {
                        do { try await pageSetManager.deletePageSet(set, mode: .withPages) } catch
                        { /* pendingError set by manager; toast surfaces */  }
                        deleteTarget = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { _ in
            Text(
                "\"Delete Set Only\" moves its Pages up into the Collection. \"Delete Set and Pages\" deletes everything."
            )
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

    /// User-defined property columns derived from `collection.views[0]` +
    /// parent vault's schema (Collections inherit schema from the parent
    /// PageType per locked decision). Empty when the SavedView has no
    /// propertyOrder configured — collapses to legacy Title/Kind/Modified.
    /// Live vault + collection from the `@Observable` manager (by id) so schema/view
    /// edits re-render the table IMMEDIATELY instead of only after a reselect — the
    /// `vault` + `collection` params are value snapshots that go stale on mutation.
    /// Collections inherit the parent Type's schema, so the schema reads from the
    /// live vault; the visible columns read from the live collection's view.
    private var liveVault: PageType {
        pageTypeManager.types.first { $0.id == vault.id } ?? vault
    }
    private var liveCollection: PageCollection {
        pageTypeManager.pageCollections(in: liveVault).first { $0.id == collection.id } ?? collection
    }

    private var userPropertyColumns: [PropertyDefinition] {
        guard let view = liveCollection.views.first else { return [] }
        let cols = PropertyColumnBuilder.columns(
            view: view,
            schema: liveVault.resolvedProperties(tierConfig: tierConfigManager.config)
        )
        return cols.compactMap { col in
            if case .userProperty(let def) = col.kind { return def }
            return nil
        }
    }

    /// Relation + tier target IDs across every visible Page row (top-level
    /// AND Set disclosure children) — drives the resolver warm so cells
    /// render icon + title instead of "(missing)".
    private var visibleContextLinkIDs: [String] {
        let relationColumns = userPropertyColumns.filter { $0.type == .relation }
        return rows.flatMap { [$0] + ($0.children ?? []) }.flatMap { row -> [String] in
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
                // coexists with the row drag instead of blocking it near the title.
                .simultaneousGesture(TapGesture(count: 2).onEnded { handleDoubleTap(row) })
                .contextMenu { menuItems(for: row) }
            }
            TableColumnForEach(userPropertyColumns, id: \.id) { def in
                TableColumn(def.name) { row in
                    if case .page(let pageMeta) = row.kind {
                        let parentSet = setContaining(pageID: pageMeta.id)
                        PropertyCellEditor(
                            definition: def,
                            value: def.type == .relation
                                ? .relation(pageMeta.frontmatter.relationIDs(forPropertyID: def.id))
                                : pageMeta.frontmatter.properties[def.id],
                            relationResolver: { contextDisplay.resolve($0) },
                            commit: { newValue in
                                Task {
                                    try? await contentManager.updatePageProperty(
                                        pageMeta,
                                        propertyID: def.id,
                                        newValue: newValue,
                                        vault: vault,
                                        collection: collection,
                                        set: parentSet
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
            // Set rows disclose their Pages (same DisclosureTableRow shape as
            // PageTypeDetailView's Collections); an empty Set renders as a
            // plain leaf row so it's visible immediately after creation.
            // Sets aren't draggable — only collection-root Page rows carry
            // the reorder drag (root-zone-only guard in handleDrop).
            ForEach(rows) { row in
                if case .set = row.kind {
                    if let kids = row.children, !kids.isEmpty {
                        DisclosureTableRow(row, isExpanded: expandedBinding(for: row.id)) {
                            ForEach(kids) { kid in
                                TableRow(kid)
                            }
                        }
                    } else {
                        TableRow(row)
                    }
                } else {
                    TableRow(row)
                        .draggable(DetailRowDragPayload(rowID: row.id))
                }
            }
            .dropDestination(for: DetailRowDragPayload.self) { offset, payloads in
                handleDrop(payloads: payloads, toOffset: offset)
            }
        }
        .task(id: visibleContextLinkIDs) {
            await contextDisplay.warm(visibleContextLinkIDs)
        }
    }

    private func propertyValue(for row: DetailRow, propertyID: String) -> PropertyValue? {
        guard case .page(let pageMeta) = row.kind else { return nil }
        return pageMeta.frontmatter.properties[propertyID]
    }

    /// Row drop handler — persists via manager. `offset` is the insertion index
    /// the table reports; unknown payloads and no-ops are dropped by the planner.
    ///
    /// Scoped to the collection-root zone: Set rows render ABOVE the root
    /// pages and aren't reorderable here, and Set pages live in disclosure
    /// children whose order belongs to each Set's own `pageOrder` — a drag
    /// that starts on or lands inside the Set zone is rejected. Offsets are
    /// translated to root-zone-local before planning.
    private func handleDrop(payloads: [DetailRowDragPayload], toOffset offset: Int) {
        guard let payload = payloads.first else { return }
        let setCount = pageSetManager.pageSets(in: collection).count
        let rootRows = Array(rows.dropFirst(setCount))
        guard rootRows.contains(where: { $0.id == payload.rowID }),
            offset >= setCount, offset <= setCount + rootRows.count
        else { return }
        guard
            let plan = DetailReorderPlanner.plan(
                rows: rootRows, movingRowID: payload.rowID, dropOffset: offset - setCount)
        else { return }
        if plan.kind == .page {
            contentManager.reorderPages(in: collection, fromOffsets: plan.fromOffsets, toOffset: plan.toOffset)
        }
    }

    private func handleDoubleTap(_ row: DetailRow) {
        switch row.kind {
        case .page(let p):
            // Open-in routing: this view knows its vault + collection, so
            // the direct variant skips parent resolution. Set pages surface
            // as disclosure children here — carry their Set into the ref.
            PageOpenRouter.routeOpen(
                p, vault: vault, collection: collection,
                set: setContaining(pageID: p.id), selection: &selection,
                openPreview: { openPagePreview($0) })
        case .collection, .set: break  // Sets have no detail view
        }
    }

    private var footer: some View {
        let setLabel = settingsManager.settings.labels.pageSet.singular
        var crumbs: [FooterCrumb] = [
            FooterCrumb(title: vault.title) { selection = .pageType(vault) },
            FooterCrumb(title: collection.title),
        ]
        if let trail = trailPage {
            if contentManager.pages(in: collection).contains(where: { $0.id == trail.id }) {
                crumbs.append(FooterCrumb(title: trail.title, isGhost: true) { selection = .page(trail) })
            } else if let set = setContaining(pageID: trail.id) {
                // Trail page lives in one of this collection's Sets — show the
                // Set as a non-clickable ghost segment ahead of the page crumb.
                crumbs.append(FooterCrumb(title: set.title, isGhost: true))
                crumbs.append(FooterCrumb(title: trail.title, isGhost: true) { selection = .page(trail) })
            }
        }
        return DetailFooterBar(crumbs: crumbs) {
            FooterAddMenuButton(
                items: [
                    .init(label: "New Page", isDisabled: isCreatingPage, action: createPage),
                    .init(label: "New \(setLabel)", isDisabled: isCreatingSet, action: createSet),
                ],
                allDisabled: isCreatingPage && isCreatingSet
            )
        }
    }

    /// Stub-and-edit "New Page" trigger fired from the detail-view footer.
    /// Mirrors PageCollectionRow's createPage — same default-title resolver,
    /// same justCreatedID + editingID flip — so the new row appears in the
    /// sidebar tree in rename mode while the detail-view list also updates.
    private func createPage() {
        guard !isCreatingPage else { return }
        isCreatingPage = true
        let existing = contentManager.pages(in: collection).map(\.title)
        let title = DefaultTitleResolver.resolve(label: "Page", existingTitles: existing)
        Task {
            defer { isCreatingPage = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await contentManager.createPage(
                            name: title, in: collection, vault: vault
                        )
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

    /// Stub-and-edit "New Set" trigger from the detail-view footer. Mirrors
    /// PageCollectionRow's createPageSet — same default-title resolver, same
    /// justCreatedID + editingID flip so the new sidebar row opens in rename
    /// mode while this view's table picks up the (empty) Set.
    private func createSet() {
        guard !isCreatingSet else { return }
        isCreatingSet = true
        let label = settingsManager.settings.labels.pageSet.singular
        let existing = pageSetManager.pageSets(in: collection).map(\.title)
        let title = DefaultTitleResolver.resolve(label: label, existingTitles: existing)
        Task {
            defer { isCreatingSet = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await pageSetManager.createPageSet(name: title, in: collection)
                    },
                    onCreate: { newSet in
                        editingID = newSet.id
                        justCreatedID = newSet.id
                    }
                )
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    /// Set rows in `pageSets(in:)` order (each carrying its pages per its own
    /// `pageOrder` as disclosure children) followed by collection-root pages
    /// (per `collection.pageOrder`) — all already resolved by the managers'
    /// load paths. Construction lives in `DetailRow.collectionRows` (pure,
    /// unit-tested).
    private var rows: [DetailRow] {
        DetailRow.collectionRows(
            sets: pageSetManager.pageSets(in: collection).map { ($0, contentManager.pages(in: $0)) },
            rootPages: contentManager.pages(in: collection)
        )
    }

    /// Stable per-row disclosure binding so a Set's expanded state survives
    /// the frequent `rows` recomputes (every manager change). Mirrors
    /// PageTypeDetailView's Collection disclosure.
    private func expandedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOn in
                if isOn { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    /// The PageSet (if any) whose loaded pages include `pageID` — nil for
    /// collection-root pages. Same in-memory parent lookup as
    /// PageTypeDetailView's `collectionContaining`; called on actions, not
    /// in render.
    private func setContaining(pageID: String) -> PageSet? {
        pageSetManager.pageSets(in: collection).first { set in
            contentManager.pages(in: set).first { $0.id == pageID } != nil
        }
    }

    @ViewBuilder
    private func menuItems(for row: DetailRow) -> some View {
        switch row.kind {
        case .page(let meta):
            Button("Edit Title") { beginRename(row) }
            Button("Edit Icon") {
                presentedSheet = .editIcon(
                    .page(meta, vault: vault, collection: collection, set: setContaining(pageID: meta.id)))
            }
            Button(row.isPinned ? "Unpin \(row.kindLabel)" : "Pin \(row.kindLabel)") {
                row.togglePin()
            }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(row) }
            }
        case .set(let set):
            // No Open (Sets have no detail view) and no Pin (containers
            // aren't pinnable from detail views) — mirrors PageTypeDetailView's
            // Collection rows otherwise.
            Button("Edit Title") { beginRename(row) }
            Button("Edit Icon") { presentedSheet = .editIcon(.pageSet(set)) }
            Divider()
            // Container delete is guarded — route through the two-mode
            // confirmation dialog (mirrors the sidebar's Set delete).
            Button("Delete", role: .destructive) {
                deleteTarget = row
            }
        case .collection:
            EmptyView()  // Collection rows never appear in this table
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    /// Title for the Set-delete confirmation. Mirrors the sidebar's
    /// `confirmationTitle` for `.deleteSet`.
    private var deleteConfirmationTitle: String {
        guard let row = deleteTarget else { return "" }
        return "Delete Set \"\(row.title)\"?"
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
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
                case .page(let p):
                    if let set = setContaining(pageID: p.id) {
                        try await contentManager.renamePage(
                            p, to: newName, in: set, collection: collection, vault: vault)
                    } else {
                        try await contentManager.renamePage(p, to: newName, in: collection, vault: vault)
                    }
                case .set(let s):
                    try await pageSetManager.renamePageSet(s, to: newName)
                case .collection:
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
            case .page(let p):
                if let set = setContaining(pageID: p.id) {
                    try await contentManager.deletePage(p, in: set)
                } else {
                    try await contentManager.deletePage(p, in: collection)
                }
            case .collection, .set:
                break  // Set deletes route through the confirmation dialog
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }
}
