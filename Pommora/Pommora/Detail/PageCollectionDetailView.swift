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

    @State private var tableSelection: Set<String> = []
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
        let cols = PropertyColumnBuilder.columns(view: view, schema: vault.properties)
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
                .draggable(DetailRowDragPayload(rowID: row.id, zone: .collectionItem))
                .dropDestination(for: DetailRowDragPayload.self) { payloads, _ in
                    handleDrop(payloads: payloads, ontoRowID: row.id)
                }
            }
            TableColumnForEach(userPropertyColumns, id: \.id) { def in
                TableColumn(def.name) { row in
                    if case .page(let pageMeta) = row.kind {
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
                                        vault: vault,
                                        collection: collection
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

    private func propertyValue(for row: DetailRow, propertyID: String) -> PropertyValue? {
        switch row.kind {
        case .page(let pageMeta):
            return pageMeta.frontmatter.properties[propertyID]
        case .collection, .item, .itemCollection:
            return nil
        }
    }

    /// Drop handler — session-only. Same-zone only. Updates `sessionOrder`,
    /// which the `rows` computed honors. Never calls a manager API.
    @discardableResult
    private func handleDrop(payloads: [DetailRowDragPayload], ontoRowID targetID: String) -> Bool {
        guard let payload = payloads.first else { return false }
        guard payload.zone == .collectionItem else { return false }
        let currentIDs = rows.map(\.id)
        let next = SessionRowOrdering.apply(base: currentIDs, movingID: payload.rowID, ontoID: targetID)
        guard next != currentIDs else { return false }
        sessionOrder = next
        return true
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
        guard let sessionOrder else { return baseRows }
        let byID = Dictionary(uniqueKeysWithValues: baseRows.map { ($0.id, $0) })
        // Honor session order for known rows; append any newly added rows at the end.
        let ordered = sessionOrder.compactMap { byID[$0] }
        let known = Set(sessionOrder)
        let appended = baseRows.filter { !known.contains($0.id) }
        return ordered + appended
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
