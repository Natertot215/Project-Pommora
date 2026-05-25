import SwiftUI

// MARK: - Sort State

/// The columns that can be sorted in PageCollectionDetailView.
enum PageCollectionSortColumn: String, CaseIterable, Sendable {
    case name
    case kind
    case modified
}

/// Encapsulates click-to-sort state for `PageCollectionDetailView`.
/// Cycle: nil → ascending → descending → nil (back to default).
/// Switching columns resets to ascending on the new column.
///
/// Extracted for direct unit-test access (J.5/J.11/K.1 pattern).
@MainActor
@Observable
final class PageCollectionDetailViewModel {

    var sortColumn: PageCollectionSortColumn?
    var sortAscending: Bool = true

    /// Advance sort state on column tap.
    func tapColumn(_ column: PageCollectionSortColumn) {
        if sortColumn == column {
            if sortAscending {
                // ascending → descending
                sortAscending = false
            } else {
                // descending → clear
                sortColumn = nil
                sortAscending = true
            }
        } else {
            // New column → ascending
            sortColumn = column
            sortAscending = true
        }
    }

    /// Returns the indicator string for the given column (▲ / ▼ / nil).
    func indicator(for column: PageCollectionSortColumn) -> String? {
        guard sortColumn == column else { return nil }
        return sortAscending ? "▲" : "▼"
    }

    /// Sort `rows` according to current sort state.
    /// When sortColumn is nil, original order is preserved (default sort).
    func sorted(_ rows: [DetailRow]) -> [DetailRow] {
        guard let col = sortColumn else { return rows }
        return rows.sorted { lhs, rhs in
            let ascending: Bool
            switch col {
            case .name:
                ascending = lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            case .kind:
                ascending = lhs.kindLabel.localizedStandardCompare(rhs.kindLabel) == .orderedAscending
            case .modified:
                ascending = lhs.modifiedAt < rhs.modifiedAt
            }
            return sortAscending ? ascending : !ascending
        }
    }
}

// MARK: - SortHeaderButton

/// A single clickable sort-column header button. Renders label + optional
/// sort indicator (▲ / ▼). Lives outside PageCollectionDetailView so it can
/// be used independently if needed.
struct SortHeaderButton: View {
    let label: String
    let indicator: String?
    var maxWidth: CGFloat? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                if let ind = indicator {
                    Text(ind)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: maxWidth ?? .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PageCollectionDetailView

struct PageCollectionDetailView: View {
    let collection: PageCollection
    let vault: PageType
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var presentedItem: Item?

    @Environment(PageContentManager.self) private var contentManager

    @State private var tableSelection: Set<String> = []
    @State private var sortVM: PageCollectionDetailViewModel = PageCollectionDetailViewModel()

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
            TextField("Name", text: $renameDraft)
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

    private var table: some View {
        VStack(spacing: 0) {
            // Clickable column-header strip (sort bar). Sits above the Table
            // rows and visually mimics a Table header. `Table(children:)` does
            // not expose a `sortOrder` binding so we implement the header
            // interaction layer here, matching the spec's "click sorts ascending;
            // second click reverses; third returns to default" requirement.
            sortHeaderBar
            Table(sortedRows, children: \.children, selection: $tableSelection) {
                TableColumn("Name") { row in
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
    }

    /// Horizontally-laid-out header buttons that drive `sortVM`. Proportions
    /// roughly match the Table column widths — not pixel-perfect, but functional.
    private var sortHeaderBar: some View {
        HStack(spacing: 0) {
            SortHeaderButton(
                label: "Name",
                indicator: sortVM.indicator(for: .name)
            ) { sortVM.tapColumn(.name) }
            SortHeaderButton(
                label: "Kind",
                indicator: sortVM.indicator(for: .kind),
                maxWidth: 120
            ) { sortVM.tapColumn(.kind) }
            SortHeaderButton(
                label: "Modified",
                indicator: sortVM.indicator(for: .modified),
                maxWidth: 200
            ) { sortVM.tapColumn(.modified) }
        }
        .background(Color(.windowBackgroundColor).opacity(0.7))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func handleDoubleTap(_ row: DetailRow) {
        switch row.kind {
        case .item(let i): presentedItem = i
        case .page(let p): selection = .page(p)
        case .collection: break
        }
    }

    private var footer: some View {
        HStack {
            Button {
                presentedSheet = .newPage(collection: collection, pageType: vault)
            } label: {
                Label("New Page", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)

            // ParadigmV2 (Task 8.1): The vestigial "New Item in PageCollection"
            // button was retired — Items live under ItemCollections (Items-side),
            // not PageCollections (Pages-side). Items-side creation will surface
            // when the Items detail surface ships in a follow-up plan.

            Spacer()
        }
        .padding(8)
    }

    private var unsortedRows: [DetailRow] {
        // ParadigmV2 (Task 5.5): Items live in ItemContentManager keyed on
        // ItemCollection now. PageCollection-side Items disappear until Phase 6
        // wires the wrapper-folder layout + ItemContentManager surfaces.
        let pages = contentManager.pages(in: collection).map { ContentItem.page($0) }
        let items: [ContentItem] = []  // TODO Phase 6: surface ItemCollection Items
        return (pages + items).map { ci in
            DetailRow(
                id: ci.id,
                title: ci.title,
                kind: detailKind(ci),
                iconName: ci.iconName,
                modifiedAt: ci.modifiedAt,
                children: nil  // v1 Collections are flat; nil = leaf row (no disclosure)
            )
        }
    }

    private var sortedRows: [DetailRow] {
        sortVM.sorted(unsortedRows)
    }

    private func detailKind(_ ci: ContentItem) -> DetailRow.Kind {
        switch ci {
        case .page(let p): return .page(p)
        case .item(let i): return .item(i)
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
        case .collection:
            EmptyView()
        }
    }

    // MARK: - Pin

    private func stateRef(for row: DetailRow) -> EntityStateRef? {
        switch row.kind {
        case .page(let p): return EntityStateRef(kind: .page, id: p.id, title: p.title)
        case .item(let i): return EntityStateRef(kind: .item, id: i.id, title: i.title)
        case .collection: return nil
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
        Task {
            do {
                switch row.kind {
                case .page(let p):
                    try await contentManager.renamePage(p, to: newName, in: collection, vault: vault)
                case .item:
                    // TODO Phase 6: route through ItemContentManager.renameItem.
                    break
                case .collection:
                    break
                }
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    // MARK: - Delete

    private func delete(_ row: DetailRow) async {
        do {
            switch row.kind {
            case .page(let p):
                try await contentManager.deletePage(p, in: collection)
            case .item:
                // TODO Phase 6: route through ItemContentManager.deleteItem.
                break
            case .collection:
                break
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }
}
