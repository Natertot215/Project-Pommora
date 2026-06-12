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
    @Environment(PageSetManager.self) private var pageSetManager
    @Environment(PageContentManager.self) private var contentManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(NexusManager.self) private var nexusManager
    @Environment(TierConfigManager.self) private var tierConfigManager
    @Environment(ContextDisplayResolver.self) private var contextDisplay
    @Environment(ActiveViewStore.self) private var activeViewStore

    // Rename alert state.
    @State private var renameTarget: RowTarget?
    @State private var renameDraft: String = ""
    /// Container-delete confirmation target — set only from a Collection group's
    /// menu. Page deletes stay direct (no confirmation); only the container
    /// case routes here, mirroring the sidebar's delete guard.
    @State private var deleteTarget: RowTarget?

    /// Bridge between the renderer's `ViewItem` + `ResolvedGroup` currency and
    /// this view's create/rename/delete logic. Private to the detail view.
    private enum RowTarget: Hashable {
        case page(ViewItem)
        case collection(PageCollection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            table
            Divider()
            footer
        }
        .task(id: pageType.id) {
            // Load Page-Type-root Pages + every PageCollection's content + every
            // Set's pages — vault scope now nests Sets under their Collection in
            // the table, so their caches must be warm too.
            await contentManager.loadAll(for: pageType)
            for coll in pageTypeManager.pageCollections(in: pageType) {
                await contentManager.loadAll(for: coll)
                for set in pageSetManager.pageSets(in: coll) {
                    await contentManager.loadAll(for: set)
                }
            }
        }
        .alert("Rename", isPresented: renameAlertBinding) {
            TextField("Title", text: $renameDraft)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            if let target = renameTarget {
                Text("Rename \(renameKindLabel(target).lowercased()) “\(renameTitle(target))”")
            }
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { target in
            Button("Delete", role: .destructive) {
                Task { await delete(target) }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { _ in
            Text("All Pages inside will be deleted.")
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

    /// Merged property schema (user properties + tier columns) for both the
    /// column resolver and the pipeline's filter / group / sort stages.
    private var schema: [PropertyDefinition] {
        livePageType.resolvedProperties(tierConfig: tierConfigManager.config)
    }

    /// The active SavedView — resolved through `ActiveViewStore` (the
    /// per-container last-active view persisted across sessions), falling back
    /// to the first view when the store has no record yet.
    private var activeView: SavedView? {
        let activeID = activeViewStore.activeViewID(for: livePageType.id)
        return livePageType.views.first(where: { $0.id == activeID }) ?? livePageType.views.first
    }

    /// Resolved, sized, icon-bearing columns for the custom table.
    private var columns: [ResolvedColumn] {
        guard let view = activeView else { return [] }
        return TableColumnResolver.resolve(view: view, schema: schema)
    }

    /// The full pipeline output, recomputed on every observed cache change so the
    /// table reflects edits instantly: source → filter → group → sort-in-group.
    private var resolvedGroups: [ResolvedGroup] {
        let items = ViewItemSource.items(
            for: .vault(livePageType),
            content: contentManager,
            sets: pageSetManager,
            collections: { pageTypeManager.pageCollections(in: $0) }
        )
        let filtered: [ViewItem] = {
            guard let filter = activeView?.filter else { return items }
            return items.filter { FilterEvaluator.matches($0.page.frontmatter, group: filter, schema: schema) }
        }()
        return GroupResolver.resolve(
            items: filtered,
            config: activeView?.group,
            scope: .vault,
            sort: activeView?.sort?.first,
            schema: schema,
            collapsed: Set(activeView?.collapsedGroups ?? [])
        )
    }

    /// Relation + tier target IDs across every visible Page — drives the resolver
    /// warm so cells render icon + title instead of "(missing)".
    private var visibleContextLinkIDs: [String] {
        let relationColumns = columns.filter { $0.kind == .property }
            .compactMap { col in schema.first(where: { $0.id == col.id }) }
            .filter { $0.type == .relation }
        return resolvedGroups.flatMap(\.flattenedItems).flatMap { item -> [String] in
            let fm = item.page.frontmatter
            let tiers = fm.tier1 + fm.tier2 + fm.tier3
            let props = relationColumns.flatMap { fm.relationIDs(forPropertyID: $0.id) }
            return tiers + props
        }
    }

    private var table: some View {
        CustomTableView(
            groups: resolvedGroups,
            columns: columns,
            layout: ColumnLayout(columns: columns),
            schema: schema,
            index: nexusManager.currentIndex,
            relationResolver: { contextDisplay.resolve($0) },
            onDoubleTap: handleDoubleTap,
            commit: { item, def, newValue in commitCell(item, def, newValue) },
            pageMenu: { AnyView(menuItems(for: .page($0))) },
            groupMenu: { AnyView(groupMenuItems(for: $0)) },
            persistWidth: { colID, width in
                editView {
                    var widths = $0.columnWidths ?? [:]
                    widths[colID] = width
                    $0.columnWidths = widths
                }
            },
            persistOrder: { newOrder in editView { $0.propertyOrder = newOrder } },
            hideColumn: { colID in
                editView { if !$0.hiddenProperties.contains(colID) { $0.hiddenProperties.append(colID) } }
            }
        )
        .task(id: visibleContextLinkIDs) {
            await contextDisplay.warm(visibleContextLinkIDs)
        }
    }

    /// Applies a `SavedView` transform to the active view on this vault's
    /// sidecar via the disk-safe `updateView` (Task 3). The container is the
    /// live PageType; the active view is `activeView` (single-view today).
    private func editView(_ transform: @escaping (inout SavedView) -> Void) {
        guard let viewID = activeView?.id else { return }
        let containerID = livePageType.id
        Task { try? await pageTypeManager.updateView(viewID, in: containerID, transform: transform) }
    }

    /// Persists a single property edit. The page's collection comes from its
    /// stamped parent — no re-lookup needed.
    private func commitCell(_ item: ViewItem, _ def: PropertyDefinition, _ newValue: PropertyValue?) {
        let parentCollection: PageCollection?
        let parentSet: PageSet?
        switch item.parent {
        case .collection(let coll, _):
            parentCollection = coll
            parentSet = nil
        case .set(let set, let coll, _):
            parentCollection = coll
            parentSet = set
        case .vaultRoot:
            parentCollection = nil
            parentSet = nil
        }
        Task {
            try? await contentManager.updatePageProperty(
                item.page,
                propertyID: def.id,
                newValue: newValue,
                vault: pageType,
                collection: parentCollection,
                set: parentSet
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        let collectionLabel = settingsManager.settings.labels.pageCollection.singular
        var crumbs: [FooterCrumb] = [FooterCrumb(title: pageType.title)]
        if let trail = trailPage,
            contentManager.pages(in: pageType).contains(where: { $0.id == trail.id })
        {
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

    // MARK: - Interaction

    private func handleDoubleTap(_ item: ViewItem) {
        // Open-in routing: rows here mix vault-root, collection, and set pages.
        // The item's stamped parent carries the exact ref, so route directly.
        PageOpenRouter.routeOpen(
            item.page, vault: item.parent.vault,
            collection: collectionOf(item), set: setOf(item),
            selection: &selection,
            openPreview: { openPagePreview($0) })
    }

    private func collectionOf(_ item: ViewItem) -> PageCollection? {
        switch item.parent {
        case .collection(let coll, _): return coll
        case .set(_, let coll, _): return coll
        case .vaultRoot: return nil
        }
    }

    private func setOf(_ item: ViewItem) -> PageSet? {
        if case .set(let set, _, _) = item.parent { return set }
        return nil
    }

    // MARK: - Context menus

    /// Page (Title-cell) menu — Edit Title / Edit Icon / Pin / Delete.
    @ViewBuilder
    private func menuItems(for target: RowTarget) -> some View {
        if case .page(let item) = target {
            let pinned = item.page.isPinned
            Button("Edit Title") { beginRename(target) }
            Button("Edit Icon") {
                presentedSheet = .editIcon(
                    .page(item.page, vault: pageType, collection: collectionOf(item), set: setOf(item)))
            }
            Button(pinned ? "Unpin Page" : "Pin Page") { item.page.togglePin() }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(target) }
            }
        }
    }

    /// Group (disclosure-row) menu. Vault scope: Collection groups carry the
    /// migrated container menu; nested Set groups never appear here (vault scope
    /// nests Sets but their container actions live in collection scope), and the
    /// headerless root band renders no group row.
    @ViewBuilder
    private func groupMenuItems(for group: ResolvedGroup) -> some View {
        if case .structuralCollection(let coll) = group.kind {
            // No Pin: containers aren't pinnable from detail views today.
            Button("Open") { selection = .collection(coll) }
            Button("Edit Title") { beginRename(.collection(coll)) }
            Button("Edit Icon") { presentedSheet = .editIcon(.pageCollection(coll)) }
            Divider()
            // Container delete is guarded — route through the confirmation
            // dialog (mirrors the sidebar). Page deletes stay direct.
            Button("Delete", role: .destructive) { deleteTarget = .collection(coll) }
        }
    }

    // MARK: - Rename

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private func renameTitle(_ target: RowTarget) -> String {
        switch target {
        case .page(let item): return item.page.title
        case .collection(let coll): return coll.title
        }
    }

    private func renameKindLabel(_ target: RowTarget) -> String {
        switch target {
        case .page: return "Page"
        case .collection: return "Collection"
        }
    }

    private func beginRename(_ target: RowTarget) {
        renameDraft = renameTitle(target)
        renameTarget = target
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        let newName = renameDraft
        renameTarget = nil
        guard !newName.isEmpty, newName != renameTitle(target) else { return }
        Task {
            do {
                switch target {
                case .collection(let coll):
                    // Collections rename via the manager directly — no parent
                    // lookup needed (the manager resolves the on-disk folder).
                    try await pageTypeManager.renamePageCollection(coll, to: newName)
                case .page(let item):
                    switch item.parent {
                    case .collection(let coll, let t):
                        try await contentManager.renamePage(item.page, to: newName, in: coll, vault: t)
                    case .set(let set, let coll, let t):
                        try await contentManager.renamePage(
                            item.page, to: newName, in: set, collection: coll, vault: t)
                    case .vaultRoot(let t):
                        try await contentManager.renamePage(item.page, to: newName, inVaultRoot: t)
                    }
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
        guard let target = deleteTarget else { return "" }
        let label = settingsManager.settings.labels.pageCollection.singular
        return "Delete \(label) \"\(renameTitle(target))\"?"
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private func delete(_ target: RowTarget) async {
        do {
            switch target {
            case .collection(let coll):
                try await pageTypeManager.deletePageCollection(coll)
            case .page(let item):
                switch item.parent {
                case .collection(let coll, _):
                    try await contentManager.deletePage(item.page, in: coll)
                case .set(let set, _, _):
                    try await contentManager.deletePage(item.page, in: set)
                case .vaultRoot(let t):
                    try await contentManager.deletePage(item.page, inVaultRoot: t)
                }
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }
}
