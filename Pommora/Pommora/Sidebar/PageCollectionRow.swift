import SwiftUI

// MARK: - Unified disclosure item

/// Combines PageSets and Pages into a single ordered list for the
/// PageCollection disclosure body — Sets render ABOVE Pages, mirroring
/// VaultDisclosureItem one level down. A single ForEach + .onMove handles
/// both, avoiding the dual-ForEach SwiftUI bug where only the first
/// ForEach's .onMove binding is honoured.
private enum CollectionDisclosureItem: Identifiable {
    case set(PageSet)
    case page(PageMeta)

    var id: String {
        switch self {
        case .set(let s): return "s:\(s.id)"
        case .page(let p): return "p:\(p.id)"
        }
    }
}

// MARK: - PageCollectionRow

struct PageCollectionRow: View {
    let collection: PageCollection
    let parentVault: PageType
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(PageSetManager.self) private var pageSetManager
    @Environment(PageContentManager.self) private var contentManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool
    @State private var expanded: Bool = false
    @State private var isCreatingPage: Bool = false
    @State private var isCreatingSet: Bool = false

    // Sets first, then collection-root pages — the same single-ForEach
    // unified list PageTypeRow uses for Collections + Pages, one level down.
    private var disclosureItems: [CollectionDisclosureItem] {
        pageSetManager.pageSets(in: collection).map { .set($0) }
            + contentManager.pages(in: collection).map { .page($0) }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(disclosureItems) { item in
                switch item {
                case .set(let set):
                    PageSetRow(
                        set: set,
                        parentCollection: collection,
                        parentVault: parentVault,
                        selection: $selection,
                        editingID: $editingID,
                        justCreatedID: $justCreatedID,
                        presentedSheet: $presentedSheet,
                        confirmingDelete: $confirmingDelete
                    )
                case .page(let page):
                    PageRow(
                        page: page,
                        parent: .collection(collection, vault: parentVault),
                        selection: $selection,
                        editingID: $editingID,
                        justCreatedID: $justCreatedID
                    )
                    .tag(SelectionTag.page(page.id))
                }
            }
            .onMove { source, destination in
                reorder(fromOffsets: source, toOffset: destination)
            }
        } label: {
            label
        }
        .listRowBackground(
            SelectionChrome(
                isSelected: SelectionTag.collection(collection.id).matches(selection)
            )
        )
        // Same pattern as PageTypeRow: load on row appearance so Pages are
        // available even when the disclosure is collapsed (count badges,
        // future search, etc.).
        .task {
            await contentManager.loadAll(for: collection)
        }
    }

    @ViewBuilder
    private var label: some View {
        if editingID == collection.id {
            RenameableRow(
                symbol: "folder",
                initialTitle: collection.title,
                draft: $draft,
                renameFocused: $renameFocused,
                onSubmit: { commit() },
                onCancel: { cancel() },
                onFocusLoss: {
                    if !isCommitting && editingID == collection.id {
                        cancel()
                    }
                },
                selectAllOnAppear: justCreatedID == collection.id
            )
        } else {
            SelectableRow(
                title: collection.title,
                symbol: "folder",
                tag: SelectionTag.collection(collection.id),
                selection: $selection,
                accent: nil
            )
            .contextMenu {
                let setLabel = settingsManager.settings.labels.pageSet.singular
                Button("New \(setLabel)") { createPageSet() }
                    .disabled(isCreatingSet)
                Button("New Page") { createPage() }
                    .disabled(isCreatingPage)
                Divider()
                Button("Edit Title") { editingID = collection.id }
                Button("Edit Icon") { presentedSheet = .editIcon(.pageCollection(collection)) }
                Divider()
                Button("Delete", role: .destructive) {
                    confirmingDelete = .deleteCollection(collection)
                }
            }
        }
    }

    /// Stub-and-edit "New Page in This Collection" trigger.
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
                            name: title, in: collection, vault: parentVault
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

    private func commit() {
        guard draft != collection.title else {
            editingID = nil
            justCreatedID = nil
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await vaultManager.renamePageCollection(collection, to: draft)
                editingID = nil
                justCreatedID = nil
            } catch {
                // pendingError set by manager; toast surfaces.
                // editingID preserved on failure for retry.
            }
        }
    }

    /// Stub-and-edit "New Set" trigger. Creates a uniquely-named PageSet on
    /// disk + in memory + in SQLite, then flips the matching sidebar row into
    /// rename mode with the default title pre-selected. `isCreatingSet`
    /// guards against rapid double-clicks producing collision toasts.
    private func createPageSet() {
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

    private func cancel() {
        editingID = nil
        justCreatedID = nil
    }

    /// Routes a drag-reorder to the correct manager — the same two-zone
    /// offset translation as PageTypeRow.reorder, one level down.
    ///
    /// Cross-set drags (a Set dragged into the pages zone, or vice versa)
    /// are silently rejected — interleaving isn't supported. Same-zone drags
    /// are translated back to per-zone offsets before forwarding.
    private func reorder(fromOffsets source: IndexSet, toOffset destination: Int) {
        let items = disclosureItems
        let setCount = pageSetManager.pageSets(in: collection).count

        // Determine which zone all source indices belong to.
        let allSets = source.allSatisfy { $0 < setCount }
        let allPages = source.allSatisfy { $0 >= setCount }

        guard allSets || allPages else { return }   // cross-zone drag — reject

        withAnimation(.snappy) {
            if allSets {
                // Clamp destination to the sets zone (indices 0..<setCount).
                let clampedDestination = min(destination, setCount)
                pageSetManager.reorderPageSets(
                    in: collection,
                    fromOffsets: source,
                    toOffset: clampedDestination
                )
            } else {
                // Translate unified-list offsets to page-local offsets.
                let localSource = IndexSet(source.map { $0 - setCount })
                let pageCount = items.count - setCount
                let rawLocal = destination - setCount
                let localDestination = min(max(rawLocal, 0), pageCount)
                contentManager.reorderPages(
                    in: collection,
                    fromOffsets: localSource,
                    toOffset: localDestination
                )
            }
        }
    }
}
