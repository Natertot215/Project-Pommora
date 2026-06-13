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
    @Environment(ActiveViewStore.self) private var activeViewStore

    @State private var renameTarget: RowTarget?
    @State private var renameDraft: String = ""
    /// Owns the row-drag mechanic + insertion/highlight state. Commit closures
    /// are wired in `.task` so they close over the live managers.
    @State private var dragCoordinator = RowDragCoordinator()
    /// Container-delete confirmation target — set only from a Set group's menu.
    /// Page deletes stay direct; the Set case routes through the same
    /// two-mode dialog the sidebar uses (Set only vs. Set and Pages).
    @State private var deleteTarget: RowTarget?
    /// The page whose cover is being set/changed via the gallery cover menu;
    /// drives the mounted `CoverPicker`'s file importer.
    @State private var coverTarget: ViewItem?
    @State private var isPickingCover: Bool = false

    /// Bridge between the renderer's `ViewItem` + `ResolvedGroup` currency and
    /// this view's create/rename/delete logic. Private to the detail view.
    private enum RowTarget: Hashable {
        case page(ViewItem)
        case set(PageSet)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            banner
            header
            Divider()
            content
            Divider()
            footer
        }
        .background { coverPickerHost }
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
            if let target = renameTarget {
                Text("Rename \(renameKindLabel(target).lowercased()) \"\(renameTitle(target))\"")
            }
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { target in
            if case .set(let set) = target {
                Button("Delete Set Only") {
                    Task {
                        do {
                            try await pageSetManager.deletePageSet(set, mode: .setOnly)
                            // Rehomed Pages land in the Collection root on disk + in
                            // the index; refresh the content cache so they surface now.
                            await contentManager.loadAll(for: collection)
                        } catch { /* pendingError set by manager; toast surfaces */  }
                        deleteTarget = nil
                    }
                }
                Button("Delete Set and Pages", role: .destructive) {
                    Task {
                        do {
                            try await pageSetManager.deletePageSet(set, mode: .withPages)
                            await contentManager.loadAll(for: collection)
                        } catch { /* pendingError set by manager; toast surfaces */  }
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

    /// Container banner area — absent entirely when no banner is set, except for
    /// a floating Add Banner affordance (handled inside `ContainerBannerView`).
    @ViewBuilder
    private var banner: some View {
        if let nexus = nexusManager.currentNexus {
            ContainerBannerView(
                containerID: liveCollection.id,
                entityID: liveCollection.id,
                bannerPath: liveCollection.banner,
                nexus: nexus)
        }
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

    /// Merged property schema (user properties + tier columns) used by both the
    /// column resolver and the pipeline's filter / group / sort stages.
    private var schema: [PropertyDefinition] {
        liveVault.resolvedProperties(tierConfig: tierConfigManager.config)
    }

    /// The active SavedView — resolved through `ActiveViewStore` (the
    /// per-container last-active view persisted across sessions), falling back
    /// to the first view when the store has no record yet.
    private var activeView: SavedView? {
        let activeID = activeViewStore.activeViewID(for: liveCollection.id)
        return liveCollection.views.first(where: { $0.id == activeID }) ?? liveCollection.views.first
    }

    /// The FULL ordered column set (hidden columns included). The table hides via
    /// native `isHidden` rather than dropping a column, so a hidden column keeps its
    /// width + position — resolve with an empty hidden set to get every column; the
    /// real hidden set travels separately as `hiddenColumnIDs`.
    private var columns: [ResolvedColumn] {
        guard var view = activeView else { return [] }
        view.hiddenProperties = []
        return TableColumnResolver.resolve(view: view, schema: schema)
    }

    /// The active view's hidden column ids — applied as `isHidden` by the table.
    private var hiddenColumnIDs: Set<String> {
        Set(activeView?.hiddenProperties ?? [])
    }

    /// SwiftUI identity for the table, unique per (collection, view). On a
    /// collection/view switch the `.id` changes, so the outline is rebuilt and
    /// `ensureColumns` re-applies THAT view's saved order/width from its sidecar — a
    /// single reused outline would otherwise keep the previous view's arrangement.
    private var tableIdentity: String {
        "viewoutline.\(liveCollection.id).\(activeView?.id ?? "default")"
    }

    /// The full pipeline output, recomputed on every observed cache change so the
    /// table reflects edits instantly: source → filter → group → sort-in-group.
    private var resolvedGroups: [ResolvedGroup] {
        let items = ViewItemSource.items(
            for: .collection(liveCollection, vault: liveVault),
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
            scope: .collection,
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

    /// Render switch on the active view's renderer kind. `.table` → the custom
    /// table; `.gallery` → the gallery grid; the remaining kinds mute to a
    /// placeholder until their renderers ship.
    @ViewBuilder
    private var content: some View {
        switch activeView?.type ?? .table {
        case .table:
            table
        case .gallery:
            galleryView
        case .board, .list, .cards:
            ContentUnavailableView(
                "View not available",
                systemImage: "rectangle.on.rectangle.slash",
                description: Text("This view type isn't rendered yet."))
        }
    }

    private var galleryView: some View {
        GalleryView(
            groups: resolvedGroups,
            view: activeView ?? SavedView(id: "view_fallback", type: .gallery),
            schema: schema,
            nexus: nexusManager.currentNexus ?? Nexus(id: "", rootURL: URL(fileURLWithPath: "/")),
            index: nexusManager.currentIndex,
            relationResolver: { contextDisplay.resolve($0) },
            onDoubleTap: handleDoubleTap,
            commit: { item, def, newValue in commitCell(item, def, newValue) },
            onRename: { beginRename(.page($0)) },
            onEditIcon: { item in
                presentedSheet = .editIcon(
                    .page(item.page, vault: vault, collection: collection, set: item.parent.set))
            },
            pageMenu: { AnyView(menuItems(for: .page($0))) },
            groupMenu: { AnyView(groupMenuItems(for: $0)) },
            coverMenu: { AnyView(coverMenuItems(for: $0)) },
            persistCollapsed: { ids in editView { $0.collapsedGroups = ids.isEmpty ? nil : ids } },
            dragCoordinator: dragCoordinator,
            buildDropContext: buildDropContext
        )
        .task(id: visibleContextLinkIDs) { await contextDisplay.warm(visibleContextLinkIDs) }
        .task { wireDragCommits() }
    }

    private var table: some View {
        ViewOutlineTable(
            groups: resolvedGroups,
            columns: columns,
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
            hiddenColumnIDs: hiddenColumnIDs,
            hideColumn: { colID in
                editView { if !$0.hiddenProperties.contains(colID) { $0.hiddenProperties.append(colID) } }
            },
            persistCollapsed: { ids in editView { $0.collapsedGroups = ids.isEmpty ? nil : ids } },
            dragCoordinator: dragCoordinator,
            buildDropContext: buildDropContext
        )
        .id(tableIdentity)
        .task(id: visibleContextLinkIDs) {
            await contextDisplay.warm(visibleContextLinkIDs)
        }
        .task { wireDragCommits() }
    }

    /// Resolves the planner `DropContext` for a drop — shared by the table and
    /// gallery renderers (identical inputs, single source). Folds in the active
    /// view's group config + manual-sort flag, which only this view knows.
    private func buildDropContext(
        _ dragged: [ViewItem], _ targetGroup: ResolvedGroup, _ insertionIndex: Int,
        _ anchorID: String?
    ) -> RowDragCoordinator.DropContext? {
        RowDragCoordinator.makeContext(
            draggedItems: dragged,
            targetGroup: targetGroup,
            insertionIndex: insertionIndex,
            anchorID: anchorID,
            group: activeView?.group,
            sortIsManual: activeView?.sort == nil,
            structuralParent: structuralParent)
    }

    /// Maps a structural `ResolvedGroup` to its `PageParent` in collection scope.
    /// Only Set groups appear here (Collection groups are vault-scope-only); the
    /// headerless root band has no structural group row.
    private func structuralParent(_ group: ResolvedGroup) -> PageParent? {
        if case .structuralSet(let set) = group.kind {
            return .set(set, collection: collection, vault: vault)
        }
        return nil
    }

    /// Wire the coordinator's commit closures to the live managers. Reorder /
    /// move / rewrite each route to the same calls the cell + menu paths use.
    private func wireDragCommits() {
        dragCoordinator.reorder = { movingIDs, anchorID, parent in
            contentManager.reorderPages(in: parent, movingIDs: movingIDs, before: anchorID)
        }
        dragCoordinator.move = { pageIDs, source, destination in
            Task { await moveDraggedPages(pageIDs, from: source, to: destination) }
        }
        dragCoordinator.rewriteProperty = { pageIDs, propertyID, value in
            Task { await rewriteDraggedProperty(pageIDs, propertyID: propertyID, value: value) }
        }
    }

    /// Move dragged pages from `source` to `destination`. Resolves each page from
    /// the live content cache (the payload is ID-only).
    private func moveDraggedPages(_ pageIDs: [String], from source: PageParent, to destination: PageParent) async {
        for id in pageIDs {
            guard let page = pageInScope(id) else { continue }
            do { try await contentManager.movePage(page, from: source, to: destination) } catch {}
        }
    }

    /// Rewrite a property across dragged pages (group-bucket drop).
    private func rewriteDraggedProperty(_ pageIDs: [String], propertyID: String, value: String?) async {
        let newValue = BucketValueDecoder.propertyValue(
            bucket: value, propertyID: propertyID, schema: schema)
        for id in pageIDs {
            guard let item = itemInScope(id) else { continue }
            do {
                try await contentManager.updatePageProperty(
                    item.page, propertyID: propertyID, newValue: newValue,
                    vault: vault, collection: collection, set: item.parent.set)
            } catch {}
        }
    }

    private func itemInScope(_ id: String) -> ViewItem? {
        resolvedGroups.flatMap(\.flattenedItems).first { $0.id == id }
    }

    private func pageInScope(_ id: String) -> PageMeta? {
        itemInScope(id)?.page
    }

    /// Applies a `SavedView` transform to the active view on this collection's
    /// sidecar via the disk-safe `updateView`. The container is the
    /// live PageCollection; the active view is `activeView` (single-view today).
    private func editView(_ transform: @escaping (inout SavedView) -> Void) {
        guard let viewID = activeView?.id else { return }
        let containerID = liveCollection.id
        Task { try? await pageTypeManager.updateView(viewID, in: containerID, transform: transform) }
    }

    /// Persists a single property edit. Set membership comes from the item's
    /// stamped parent — no re-lookup needed.
    private func commitCell(_ item: ViewItem, _ def: PropertyDefinition, _ newValue: PropertyValue?) {
        Task {
            try? await contentManager.updatePageProperty(
                item.page,
                propertyID: def.id,
                newValue: newValue,
                vault: vault,
                collection: collection,
                set: item.parent.set
            )
        }
    }

    private func handleDoubleTap(_ item: ViewItem) {
        // Open-in routing: this view knows its vault + collection, so the direct
        // variant skips parent resolution. Set pages carry their Set into the ref.
        PageOpenRouter.routeOpen(
            item.page, vault: vault, collection: collection,
            set: item.parent.set, selection: &selection,
            openPreview: { openPagePreview($0) })
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

    /// The PageSet (if any) whose loaded pages include `pageID` — nil for
    /// collection-root pages. Used by the footer trail crumb; page-action paths
    /// read the `ViewItem`'s stamped parent instead.
    private func setContaining(pageID: String) -> PageSet? {
        pageSetManager.pageSets(in: collection).first { set in
            contentManager.pages(in: set).first { $0.id == pageID } != nil
        }
    }

    // MARK: - Cover

    /// Mounts the cover importer for `coverTarget` (the gallery cover menu sets
    /// it then flips `isPickingCover`). Invisible — purely hosts the fileImporter.
    @ViewBuilder
    private var coverPickerHost: some View {
        if let item = coverTarget, let nexus = nexusManager.currentNexus {
            CoverPicker(
                page: item.page, vault: vault, collection: collection, set: item.parent.set,
                nexus: nexus, isPresenting: $isPickingCover)
        }
    }

    /// Cover-area context menu (gallery) — Set / Change / Remove Cover. Set/Change
    /// open the importer; Remove writes `cover = nil` via updatePageFrontmatter.
    @ViewBuilder
    private func coverMenuItems(for item: ViewItem) -> some View {
        let hasCover = item.page.frontmatter.cover != nil
        Button(hasCover ? "Change Cover" : "Set Cover") {
            coverTarget = item
            isPickingCover = true
        }
        if hasCover {
            Button("Remove Cover", role: .destructive) { removeCover(item) }
        }
    }

    private func removeCover(_ item: ViewItem) {
        let previousCover = item.page.frontmatter.cover
        var fm = item.page.frontmatter
        fm.cover = nil
        Task {
            do {
                try await contentManager.updatePageFrontmatter(
                    item.page, frontmatter: fm, vault: vault, collection: collection,
                    set: item.parent.set)
                // Delete the cleared cover file ONLY AFTER the `cover = nil`
                // write succeeds, so a failed write never leaves `cover`
                // pointing at a deleted file.
                if let nexus = nexusManager.currentNexus {
                    CoverAssetStore().delete(relativePath: previousCover, for: item.page.id, in: nexus)
                }
            } catch {}
        }
    }

    // MARK: - Context menus

    /// Page (Title-cell) menu — Edit Title / Edit Icon / Pin / Delete. Set
    /// membership comes from the item's stamped parent.
    @ViewBuilder
    private func menuItems(for target: RowTarget) -> some View {
        if case .page(let item) = target {
            let pinned = item.page.isPinned
            Button("Edit Title") { beginRename(target) }
            Button("Edit Icon") {
                presentedSheet = .editIcon(
                    .page(item.page, vault: vault, collection: collection, set: item.parent.set))
            }
            Button(pinned ? "Unpin Page" : "Pin Page") { item.page.togglePin() }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(target) }
            }
        }
    }

    /// Group (disclosure-row) menu. Collection groups never appear in this scope;
    /// Set groups carry the migrated container menu. The headerless ungrouped
    /// band renders no group row, so its menu is empty.
    @ViewBuilder
    private func groupMenuItems(for group: ResolvedGroup) -> some View {
        if case .structuralSet(let set) = group.kind {
            // No Open (Sets have no detail view) and no Pin (containers aren't
            // pinnable from detail views).
            Button("Edit Title") { beginRename(.set(set)) }
            Button("Edit Icon") { presentedSheet = .editIcon(.pageSet(set)) }
            Divider()
            // Container delete is guarded — route through the two-mode
            // confirmation dialog (mirrors the sidebar's Set delete).
            Button("Delete", role: .destructive) { deleteTarget = .set(set) }
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    // MARK: - RowTarget label helpers

    private func renameTitle(_ target: RowTarget) -> String {
        switch target {
        case .page(let item): return item.page.title
        case .set(let set): return set.title
        }
    }

    private func renameKindLabel(_ target: RowTarget) -> String {
        switch target {
        case .page: return "Page"
        case .set: return "Set"
        }
    }

    /// Title for the Set-delete confirmation. Mirrors the sidebar's
    /// `confirmationTitle` for `.deleteSet`.
    private var deleteConfirmationTitle: String {
        guard let target = deleteTarget else { return "" }
        return "Delete Set \"\(renameTitle(target))\"?"
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
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
                case .page(let item):
                    if case .set(let set, _, _) = item.parent {
                        try await contentManager.renamePage(
                            item.page, to: newName, in: set, collection: collection, vault: vault)
                    } else {
                        try await contentManager.renamePage(
                            item.page, to: newName, in: collection, vault: vault)
                    }
                case .set(let set):
                    try await pageSetManager.renamePageSet(set, to: newName)
                }
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    private func delete(_ target: RowTarget) async {
        do {
            switch target {
            case .page(let item):
                if case .set(let set, _, _) = item.parent {
                    try await contentManager.deletePage(item.page, in: set)
                } else {
                    try await contentManager.deletePage(item.page, in: collection)
                }
            case .set:
                break  // Set deletes route through the confirmation dialog
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }
}
