import SwiftUI

/// The single shared detail view behind `PageCollectionDetailView` (vault scope) and
/// `CollectionSetDetailView` (collection scope). Owns the whole render skeleton,
/// the pipeline computeds, the drag/cover/rename/delete machinery, and ALL view
/// state. Everything that genuinely differs between the two scopes is read off
/// the injected `scope` (a `DetailScope` value witness) or off each item's
/// stamped `item.parent.*` — `ViewSurface` never branches on which scope it is.
///
/// The two scopes pass exactly the snapshots `ViewItemSource` re-stamps onto each
/// `ViewItem.parent`, so reading `item.parent.pageCollection` / `.collection` / `.set` is
/// byte-equivalent to passing the container snapshots through (the accidental
/// per-view diff the old two-view split carried).
struct ViewSurface<Scope: DetailScope>: View {
    let scope: Scope
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    /// Last page visited before navigating back here; shown as a ghost trail
    /// crumb if the page lives in this scope.
    var trailPage: PageMeta?

    @State private var isCreatingPage: Bool = false
    /// One container-create flag — only this scope's container kind flips it.
    @State private var isCreatingContainer: Bool = false

    @Environment(PageCollectionManager.self) var collectionManager
    @Environment(PageSetManager.self) var pageSetManager
    @Environment(PageContentManager.self) var contentManager
    @Environment(SettingsManager.self) var settingsManager
    @Environment(NexusManager.self) var nexusManager
    @Environment(TierConfigManager.self) private var tierConfigManager
    @Environment(ContextDisplayResolver.self) private var contextDisplay
    @Environment(ActiveViewStore.self) private var activeViewStore

    // Rename alert state.
    @State var renameTarget: RowTarget?
    @State var renameDraft: String = ""
    /// Owns the row-drag mechanic + insertion/highlight state. The ONE shared
    /// instance — its commit closures are wired in `.task`.
    @State private var dragCoordinator = RowDragCoordinator()
    /// Container-delete confirmation target — set only from a container group's
    /// menu. Page deletes stay direct (no confirmation); only the container case
    /// routes here, mirroring the sidebar's delete guard.
    @State var deleteTarget: ContainerRef?
    /// The page whose cover is being set/changed via the gallery cover menu.
    @State var coverTarget: ViewItem?
    @State var isPickingCover: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRegion
            Divider()
            content
            Divider()
            footer
        }
        .background { coverPickerHost }
        .task(id: scope.containerID(collectionManager)) {
            await scope.warmCaches(
                content: contentManager, sets: pageSetManager, types: collectionManager)
        }
        .alert("Rename", isPresented: renameAlertBinding) {
            TextField("Title", text: $renameDraft)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            if let target = renameTarget {
                let q = scope.renameQuotes
                Text("Rename \(renameKindLabel(target).lowercased()) \(q.open)\(renameTitle(target))\(q.close)")
            }
        }
        .confirmationDialog(
            deleteConfirmation?.title ?? "",
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible,
            presenting: deleteConfirmation
        ) { confirmation in
            deleteConfirmationActions(confirmation)
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    // MARK: - Header

    /// Banner + title region. With a banner active the title overlays the banner
    /// (bottom-leading); otherwise the banner area (Add Banner affordance) sits
    /// above a plain, larger title in normal chrome.
    @ViewBuilder
    private var headerRegion: some View {
        if bannerActive {
            // `backgroundExtensionEffect()` is Apple's Liquid-Glass modifier that
            // extends + blurs the banner under the sidebar / inspector / toolbar
            // for a full edge-to-edge header (the Landmarks-sample pattern); the
            // title rides at its bottom-leading and stays out of the side panels.
            banner
                .backgroundExtensionEffect()
                .overlay(alignment: .bottomLeading) {
                    titleLabel
                        .padding(.horizontal, PUI.DetailHeader.paddingHorizontal)
                        .padding(.bottom, PUI.DetailHeader.overlayInset)
                }
        } else {
            banner
            header
        }
    }

    private var header: some View {
        HStack {
            titleLabel
            Spacer()
        }
        .padding(.horizontal, PUI.DetailHeader.paddingHorizontal)
        .padding(.vertical, PUI.DetailHeader.paddingVertical)
    }

    /// The detail title — icon + title at the detail-header font, with the shared
    /// interaction (right-click → Rename / Change Icon, inline rename, anchored
    /// picker). Rides over the banner (bottom-leading) when one is active.
    private var titleLabel: some View {
        DetailTitleHeader(
            title: scope.headerTitle,
            icon: scope.headerIcon,
            titleFont: PUI.DetailHeader.titleFont,
            iconFont: PUI.DetailHeader.titleFont,
            plainField: true,
            onRename: { newTitle in try? await scope.renameHeader(to: newTitle, types: collectionManager) },
            onIconChange: { newIcon in try? await scope.updateHeaderIcon(to: newIcon, types: collectionManager) }
        )
    }

    /// True when this container has a banner image AND the active view shows it —
    /// the only state where the title overlays the banner.
    private var bannerActive: Bool {
        scope.containerBanner(collectionManager) != nil && (activeView?.showBanner ?? true)
    }

    /// Container banner — absent unless set, with a floating Add Banner
    /// affordance in the no-banner state (handled by `ContainerBannerView`).
    @ViewBuilder
    private var banner: some View {
        if let nexus = nexusManager.currentNexus {
            ContainerBannerView(
                containerID: scope.containerID(collectionManager),
                bannerPath: scope.containerBanner(collectionManager),
                isVisible: activeView?.showBanner ?? true,
                nexus: nexus)
        }
    }

    // MARK: - Pipeline computeds

    /// The live PageCollection supplying schema + tier columns (live so schema/view
    /// edits re-render immediately, not only after a reselect).
    private var schemaSource: PageCollection {
        scope.schemaSource(collectionManager)
    }

    /// Merged property schema (user properties + tier columns) for both the
    /// column resolver and the pipeline's filter / group / sort stages.
    private var schema: [PropertyDefinition] {
        schemaSource.resolvedProperties(tierConfig: tierConfigManager.config)
    }

    /// The active SavedView — resolved through `ActiveViewStore` (the
    /// per-container last-active view persisted across sessions), falling back
    /// to the first view when the store has no record yet.
    private var activeView: SavedView? {
        activeViewStore.resolvedActiveView(
            in: scope.containerID(collectionManager), manager: collectionManager)
    }

    /// The FULL ordered column set (hidden columns included). The table hides via
    /// native `isHidden` rather than dropping a column, so a hidden column keeps its
    /// width + position — resolve with an empty hidden set to get every column; the
    /// real hidden set travels separately as `hiddenColumnIDs`.
    private var columns: [ResolvedColumn] {
        guard var view = activeView else { return [] }
        view.hiddenProperties = []
        var resolved = TableColumnResolver.resolve(view: view, schema: schema)
        // Status grouping moves the Status column first (transient — the saved
        // column order is untouched; it returns when grouping changes).
        if isStatusGrouping, let statusID = groupingProperty?.id,
            let idx = resolved.firstIndex(where: { $0.id == statusID })
        {
            resolved.insert(resolved.remove(at: idx), at: 0)
        }
        return resolved
    }

    /// The active view's hidden column ids — applied as `isHidden` by the table.
    /// While grouping by Status the Status column is force-shown (the disclosure
    /// lives there), regardless of its saved hidden state.
    private var hiddenColumnIDs: Set<String> {
        var hidden = Set(activeView?.hiddenProperties ?? [])
        if isStatusGrouping, let statusID = groupingProperty?.id { hidden.remove(statusID) }
        return hidden
    }

    /// The active grouping property, when the view groups by a property (nil for
    /// structural / flat / no grouping). Drives the group-header pill + icon.
    private var groupingProperty: PropertyDefinition? {
        guard case .property(let grouping)? = activeView?.group else { return nil }
        return schema.first(where: { $0.id == grouping.propertyID })
    }

    /// Grouping by a Status property gets the special arrangement: the Status
    /// column moves first, becomes the disclosure column, and force-shows.
    private var isStatusGrouping: Bool { groupingProperty?.type == .status }

    /// The column that carries the disclosure + group headers — the Status column
    /// while grouping by Status, the Title column otherwise.
    private var outlineColumnID: String {
        isStatusGrouping ? (groupingProperty?.id ?? ReservedPropertyID.title) : ReservedPropertyID.title
    }

    /// SwiftUI identity for the table, unique per (container, view). On a
    /// container/view switch the `.id` changes, so the outline is rebuilt and
    /// `ensureColumns` re-applies THAT view's saved order/width from its sidecar — a
    /// single reused outline would otherwise keep the previous view's arrangement.
    private var tableIdentity: String {
        // The disclosure column is folded in: switching it (Title ⇄ Status) rebuilds
        // the outline so columns re-add in the new order with the right outline column.
        "viewoutline.\(scope.containerID(collectionManager)).\(activeView?.id ?? "default").\(outlineColumnID)"
    }

    /// The full pipeline output, recomputed on every observed cache change so the
    /// table reflects edits instantly: source → filter → group → sort-in-group.
    private var resolvedGroups: [ResolvedGroup] {
        let items = ViewItemSource.items(
            for: scope.itemScope(collectionManager),
            content: contentManager,
            sets: pageSetManager,
            collections: { collectionManager.pageCollections(in: $0) }
        )
        let filtered: [ViewItem] = {
            guard let filter = activeView?.filter else { return items }
            return items.filter { FilterEvaluator.matches($0.page.frontmatter, group: filter, schema: schema) }
        }()
        return GroupResolver.resolve(
            items: filtered,
            config: activeView?.group,
            scope: scope.groupScope,
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

    /// Render switch on the active view's renderer kind.
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
            onOpenGroup: openGroup,
            commit: { item, def, newValue in commitCell(item, def, newValue) },
            onRename: { beginRename(.page($0)) },
            onEditIcon: { item in
                presentedSheet = .editIcon(
                    .page(
                        item.page, pageCollection: item.parent.pageCollection,
                        collection: item.parent.collection, set: item.parent.set))
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
            groupingProperty: groupingProperty,
            outlineColumnID: outlineColumnID,
            index: nexusManager.currentIndex,
            relationResolver: { contextDisplay.resolve($0) },
            onDoubleTap: handleDoubleTap,
            onOpenGroup: openGroup,
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

    // MARK: - Drag

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
            structuralParent: { scope.structuralParent($0, collectionManager) })
    }

    /// Wire the coordinator's commit closures to the live managers.
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

    private func moveDraggedPages(_ pageIDs: [String], from source: PageParent, to destination: PageParent) async {
        for id in pageIDs {
            guard let page = itemInScope(id)?.page else { continue }
            do { try await contentManager.movePage(page, from: source, to: destination) } catch {}
        }
    }

    private func rewriteDraggedProperty(_ pageIDs: [String], propertyID: String, value: String?) async {
        let newValue = BucketValueDecoder.propertyValue(
            bucket: value, propertyID: propertyID, schema: schema)
        for id in pageIDs {
            guard let item = itemInScope(id) else { continue }
            do {
                try await contentManager.updatePageProperty(
                    item.page, propertyID: propertyID, newValue: newValue,
                    pageCollection: item.parent.pageCollection, collection: item.parent.collection, set: item.parent.set)
            } catch {}
        }
    }

    private func itemInScope(_ id: String) -> ViewItem? {
        resolvedGroups.flatMap(\.flattenedItems).first { $0.id == id }
    }

    /// Applies a `SavedView` transform to the active view on this scope's
    /// container sidecar via the disk-safe `updateView` (single-view today).
    private func editView(_ transform: @escaping (inout SavedView) -> Void) {
        guard let viewID = activeView?.id else { return }
        let containerID = scope.containerID(collectionManager)
        Task { try? await collectionManager.updateView(viewID, in: containerID, transform: transform) }
    }

    /// Persists a single property edit. The page's parent comes from its stamped
    /// `item.parent` — no re-lookup needed.
    private func commitCell(_ item: ViewItem, _ def: PropertyDefinition, _ newValue: PropertyValue?) {
        Task {
            try? await contentManager.updatePageProperty(
                item.page,
                propertyID: def.id,
                newValue: newValue,
                pageCollection: item.parent.pageCollection,
                collection: item.parent.collection,
                set: item.parent.set
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        let crumbs = scope.footerCrumbs(
            trailPage: trailPage, content: contentManager, sets: pageSetManager,
            select: { selection = $0 })
        let containerLabel = scope.containerCreateLabel(settingsManager)
        return DetailFooterBar(crumbs: crumbs) {
            FooterAddMenuButton(
                items: [
                    .init(label: "New Page", isDisabled: isCreatingPage, action: createPage),
                    .init(label: "New \(containerLabel)", isDisabled: isCreatingContainer, action: createContainer),
                ],
                allDisabled: isCreatingPage && isCreatingContainer
            )
        }
    }

    /// Stub-and-edit "New Page" trigger from the footer. Page lives at this scope's
    /// root; `editingID` flip lights up rename-mode on the newly-created row.
    private func createPage() {
        guard !isCreatingPage else { return }
        isCreatingPage = true
        let existing = scope.existingPageTitles(contentManager)
        let title = DefaultTitleResolver.resolve(label: "Page", existingTitles: existing)
        Task {
            defer { isCreatingPage = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: { try await scope.createPage(title: title, content: contentManager) },
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

    /// Stub-and-edit "New <container>" trigger from the footer (a Collection in
    /// vault scope, a Set in collection scope).
    private func createContainer() {
        guard !isCreatingContainer else { return }
        isCreatingContainer = true
        let label = scope.containerCreateLabel(settingsManager)
        let existing = scope.existingContainerTitles(types: collectionManager, sets: pageSetManager)
        let title = DefaultTitleResolver.resolve(label: label, existingTitles: existing)
        Task {
            defer { isCreatingContainer = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await scope.createContainer(
                            title: title, types: collectionManager, sets: pageSetManager)
                    },
                    onCreate: { newID in
                        editingID = newID
                        justCreatedID = newID
                    }
                )
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    // MARK: - Interaction

    /// Opens a structural group's detail view on double-click — Collections open
    /// their detail; Sets have none, so this no-ops. Shared by the table + gallery
    /// so the group-open behavior lives in one place (layout-agnostic).
    private func openGroup(_ group: ResolvedGroup) {
        if case .structuralCollection(let coll) = group.kind {
            selection = .collection(coll)
        }
    }

    private func handleDoubleTap(_ item: ViewItem) {
        // Open-in routing: rows here mix vault-root, collection, and set pages.
        // The item's stamped parent carries the exact ref, so route directly.
        PageOpenRouter.routeOpen(
            item.page, pageCollection: item.parent.pageCollection,
            collection: item.parent.collection, set: item.parent.set,
            selection: &selection,
            openPreview: { openPagePreview($0) })
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
                    .page(
                        item.page, pageCollection: item.parent.pageCollection,
                        collection: item.parent.collection, set: item.parent.set))
            }
            Button(pinned ? "Unpin Page" : "Pin Page") { item.page.togglePin() }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(target) }
            }
        }
    }

    /// Group (disclosure-row) menu. The scope supplies the container actions for a
    /// structural group (nil for the headerless ungrouped band); `ViewSurface`
    /// renders + routes each intent uniformly.
    @ViewBuilder
    private func groupMenuItems(for group: ResolvedGroup) -> some View {
        if let actions = scope.containerActions(for: group) {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                containerMenuButton(action)
            }
        }
    }

    @ViewBuilder
    private func containerMenuButton(_ action: ContainerMenuAction) -> some View {
        switch action {
        case .open(let sel):
            Button("Open") { selection = sel }
        case .editTitle(let ref):
            Button("Edit Title") { beginRename(.container(ref)) }
        case .editIcon(let target):
            Button("Edit Icon") { presentedSheet = .editIcon(target) }
        case .delete(let ref):
            // Container delete is guarded — route through the confirmation
            // dialog (mirrors the sidebar). Page deletes stay direct.
            Divider()
            Button("Delete", role: .destructive) { deleteTarget = ref }
        }
    }

}
