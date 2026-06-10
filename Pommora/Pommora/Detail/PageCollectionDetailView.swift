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

    @Environment(PageContentManager.self) private var contentManager
    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(NexusManager.self) private var nexusManager
    @Environment(TierConfigManager.self) private var tierConfigManager
    @Environment(ContextDisplayResolver.self) private var contextDisplay
    @Environment(\.openWindow) private var openWindow

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
        .task(id: collection.id) {
            await contentManager.loadAll(for: collection)
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
    /// visibleProperties configured — collapses to legacy Title/Kind/Modified.
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

    /// Relation + tier target IDs across every visible Page row — drives the
    /// resolver warm so cells render icon + title instead of "(missing)".
    private var visibleContextLinkIDs: [String] {
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
                // coexists with the row drag instead of blocking it near the title.
                .simultaneousGesture(TapGesture(count: 2).onEnded { handleDoubleTap(row) })
                .contextMenu { menuItems(for: row) }
            }
            TableColumnForEach(userPropertyColumns, id: \.id) { def in
                TableColumn(def.name) { row in
                    if case .page(let pageMeta) = row.kind {
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
                                        collection: collection
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
            // Row-level drag = reorder (table-specialized API). Selection
            // highlight removed so the drag owns the gesture; multi-select
            // returns as a hover checkbox in v0.4.0.
            ForEach(rows) { row in
                TableRow(row)
                    .draggable(DetailRowDragPayload(rowID: row.id))
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
    private func handleDrop(payloads: [DetailRowDragPayload], toOffset offset: Int) {
        guard let payload = payloads.first else { return }
        guard let plan = DetailReorderPlanner.plan(rows: rows, movingRowID: payload.rowID, dropOffset: offset) else {
            return
        }
        if plan.kind == .page {
            contentManager.reorderPages(in: collection, fromOffsets: plan.fromOffsets, toOffset: plan.toOffset)
        }
    }

    private func handleDoubleTap(_ row: DetailRow) {
        switch row.kind {
        case .page(let p):
            // Open-in routing: this view knows its vault + collection, so
            // the direct variant skips parent resolution.
            PageOpenRouter.routeOpen(
                p, vault: vault, collection: collection, selection: &selection,
                openPreview: { openWindow(id: "page-preview", value: $0) })
        case .collection: break
        }
    }

    private var footer: some View {
        var crumbs: [FooterCrumb] = [
            FooterCrumb(title: vault.title) { selection = .pageType(vault) },
            FooterCrumb(title: collection.title),
        ]
        if let trail = trailPage,
            contentManager.pages(in: collection).contains(where: { $0.id == trail.id })
        {
            crumbs.append(FooterCrumb(title: trail.title, isGhost: true) { selection = .page(trail) })
        }
        return DetailFooterBar(crumbs: crumbs) {
            FooterAddMenuButton(
                items: [.init(label: "New Page", isDisabled: isCreatingPage, action: createPage)],
                allDisabled: isCreatingPage
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

    private var rows: [DetailRow] {
        contentManager.pages(in: collection).map { p in
            DetailRow(
                id: "page-\(p.id)",
                title: p.title,
                kind: .page(p),
                iconName: p.frontmatter.icon ?? "doc.text",
                modifiedAt: p.frontmatter.createdAt,
                children: nil
            )
        }
    }

    @ViewBuilder
    private func menuItems(for row: DetailRow) -> some View {
        switch row.kind {
        case .page(let meta):
            Button("Edit Title") { beginRename(row) }
            Button("Edit Icon") {
                presentedSheet = .editIcon(.page(meta, vault: vault, collection: collection))
            }
            Button(row.isPinned ? "Unpin \(row.kindLabel)" : "Pin \(row.kindLabel)") {
                row.togglePin()
            }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(row) }
            }
        case .collection:
            EmptyView()  // containers aren't context-menu targets here
        }
    }

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
                case .page(let p):
                    try await contentManager.renamePage(p, to: newName, in: collection, vault: vault)
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
                try await contentManager.deletePage(p, in: collection)
            case .collection:
                break
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }
}
