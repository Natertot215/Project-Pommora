import SwiftUI

struct PageCollectionDetailView: View {
    let collection: PageCollection
    let vault: PageType
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var presentedItem: Item?
    @Binding var editingID: String?
    @Binding var justCreatedID: String?

    @State private var isCreatingPage: Bool = false

    @Environment(PageContentManager.self) private var contentManager
    @Environment(NexusManager.self) private var nexusManager
    @Environment(TierConfigManager.self) private var tierConfigManager
    @Environment(RelationDisplayResolver.self) private var relationDisplay

    @State private var renameTarget: DetailRow?
    @State private var renameDraft: String = ""
    /// Session-local row order override. Nil → fall back to manager order.
    /// Resets on entity change (.task(id:)) per spec. Independent of the
    /// sidebar's persistent reorder system.
    @State private var sessionOrder: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            table
            Divider()
            footer
        }
        .task(id: collection.id) {
            sessionOrder = nil
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
    private var userPropertyColumns: [PropertyDefinition] {
        guard let view = collection.views.first else { return [] }
        let cols = PropertyColumnBuilder.columns(
            view: view,
            schema: vault.resolvedProperties(tierConfig: tierConfigManager.config)
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
                            relationResolver: { relationDisplay.resolve($0) },
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
                            relationResolver: { relationDisplay.resolve($0) }
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
        .task(id: visibleRelationIDs) {
            await relationDisplay.warm(visibleRelationIDs)
        }
    }

    private func propertyValue(for row: DetailRow, propertyID: String) -> PropertyValue? {
        switch row.kind {
        case .page(let pageMeta):
            return pageMeta.frontmatter.properties[propertyID]
        case .collection, .item, .itemCollection:
            return nil
        }
    }

    /// Row drop handler — session-only. `offset` is the insertion index the
    /// table reports; `move` no-ops on unknown payloads. Updates `sessionOrder`,
    /// which the `rows` computed honors. Never calls a manager API.
    private func handleDrop(payloads: [DetailRowDragPayload], toOffset offset: Int) {
        guard let payload = payloads.first else { return }
        let currentIDs = rows.map(\.id)
        let next = SessionRowOrdering.move(base: currentIDs, movingID: payload.rowID, toOffset: offset)
        guard next != currentIDs else { return }
        sessionOrder = next
    }

    private func handleDoubleTap(_ row: DetailRow) {
        switch row.kind {
        case .item(let i): presentedItem = i
        case .page(let p): selection = .page(p)
        case .collection, .itemCollection: break
        }
    }

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
            Spacer()
        }
        .padding(8)
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
        // ParadigmV2 (Task 5.5): Items live in ItemContentManager keyed on
        // ItemCollection now. PageCollection-side Items disappear until a
        // future plan surfaces cross-side embedding (out of scope here).
        let pages = contentManager.pages(in: collection).map { ContentItem.page($0) }
        let items: [ContentItem] = []
        let baseRows: [DetailRow] = (pages + items).map { ci in
            DetailRow(
                id: ci.id,
                title: ci.title,
                kind: detailKind(ci),
                iconName: ci.iconName,
                modifiedAt: ci.modifiedAt,
                children: nil
            )
        }
        // Honor session order for known rows; append any newly added rows at the end.
        return SessionRowOrdering.reconcile(base: baseRows, sessionOrder: sessionOrder)
    }

    private func detailKind(_ ci: ContentItem) -> DetailRow.Kind {
        switch ci {
        case .page(let p): return .page(p)
        case .item(let i): return .item(i)
        }
    }

    @ViewBuilder
    private func menuItems(for row: DetailRow) -> some View {
        switch row.kind {
        case .page, .item:
            Button("Rename") { beginRename(row) }
            Button(row.isPinned ? "Unpin \(row.kindLabel)" : "Pin \(row.kindLabel)") {
                row.togglePin()
            }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(row) }
            }
        case .collection, .itemCollection:
            EmptyView()
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
                case .item:
                    break  // Items rename via Item Window
                case .collection, .itemCollection:
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
            case .item:
                break
            case .collection, .itemCollection:
                break
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }
}
