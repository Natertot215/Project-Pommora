import SwiftUI

/// Detail surface for a selected Folder (third tier on the Pages side).
/// Structural mirror of `PageCollectionDetailView`, scoped one level deeper:
/// a Folder holds Pages only (no nested Folders or Collections), so the table
/// is a flat page list. Property columns derive from the Folder's own
/// `views[0]` against the grandparent PageType's schema (Folders inherit
/// schema, edit views independently — locked decision).
struct FolderDetailView: View {
    let folder: Folder
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
    @State private var sessionOrder: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            table
            Divider()
            footer
        }
        .task(id: folder.id) {
            sessionOrder = nil
            await contentManager.loadAll(for: folder)
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
                Text(folder.title)
            } icon: {
                Image(systemName: folder.icon ?? "folder")
            }
            .font(.title2.bold())
            Spacer()
        }
        .padding()
    }

    /// User-defined property columns derived from `folder.views[0]` + the
    /// grandparent vault's schema (Folders inherit schema per locked decision).
    private var userPropertyColumns: [PropertyDefinition] {
        guard let view = folder.views.first else { return [] }
        let cols = PropertyColumnBuilder.columns(view: view, schema: vault.properties)
        return cols.compactMap { col in
            if case .userProperty(let def) = col.kind { return def }
            return nil
        }
    }

    private var table: some View {
        Table(rows, selection: $tableSelection) {
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
                                        collection: nil
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
            TableColumn("Modified") { row in
                Text(row.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .width(min: 140, ideal: 180, max: 240)
        }
    }

    private func handleDoubleTap(_ row: DetailRow) {
        switch row.kind {
        case .page(let p): selection = .page(p)
        case .item, .collection, .itemCollection: break
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

    /// Stub-and-edit "New Page" trigger fired from the Folder detail footer.
    /// Creates a Page inside the Folder, then flips its sidebar row into
    /// rename mode (mirrors the Collection-scoped variant one tier up).
    private func createPage() {
        guard !isCreatingPage else { return }
        isCreatingPage = true
        let existing = contentManager.pages(in: folder).map(\.title)
        let title = DefaultTitleResolver.resolve(label: "Page", existingTitles: existing)
        Task {
            defer { isCreatingPage = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await contentManager.createPage(
                            name: title, in: folder, vault: vault
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
        let baseRows: [DetailRow] = contentManager.pages(in: folder).map { page in
            DetailRow(
                id: page.id,
                title: page.title,
                kind: .page(page),
                iconName: "doc.text",
                // PageMeta doesn't carry a separate mtime; fall back to
                // createdAt, mirroring ContentItem.modifiedAt's page case.
                modifiedAt: page.frontmatter.createdAt,
                children: nil
            )
        }
        guard let sessionOrder else { return baseRows }
        let byID = Dictionary(uniqueKeysWithValues: baseRows.map { ($0.id, $0) })
        let ordered = sessionOrder.compactMap { byID[$0] }
        let known = Set(sessionOrder)
        let appended = baseRows.filter { !known.contains($0.id) }
        return ordered + appended
    }

    @ViewBuilder
    private func menuItems(for row: DetailRow) -> some View {
        switch row.kind {
        case .page:
            Button("Rename") { beginRename(row) }
            Button(isPinned(row) ? "Unpin Page" : "Pin Page") { togglePin(row) }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(row) }
            }
        case .item, .collection, .itemCollection:
            EmptyView()
        }
    }

    private func stateRef(for row: DetailRow) -> EntityStateRef? {
        switch row.kind {
        case .page(let p): return EntityStateRef(kind: .page, id: p.id, title: p.title)
        case .item, .collection, .itemCollection: return nil
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
                if case .page(let p) = row.kind {
                    try await contentManager.renamePage(p, to: newName, in: folder, vault: vault)
                }
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    private func delete(_ row: DetailRow) async {
        do {
            if case .page(let p) = row.kind {
                try await contentManager.deletePage(p, in: folder)
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }
}
