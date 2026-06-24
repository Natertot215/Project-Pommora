import SwiftUI

// MARK: - Unified disclosure item

/// Combines PageSets and Pages into a single ordered list for the
/// PageCollection disclosure body — Sets render ABOVE Pages. A single ForEach +
/// .onMove handles both, avoiding the dual-ForEach SwiftUI bug where only the
/// first ForEach's .onMove binding is honoured.
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
    let collection: PageSet
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

    @State private var expanded: Bool = false
    @State private var isCreatingPage: Bool = false
    @State private var isCreatingSet: Bool = false

    // Sets first, then collection-root pages — the same single-ForEach unified
    // list PageTypeRow uses one level up.
    private var disclosureItems: [CollectionDisclosureItem] {
        pageSetManager.pageSets(in: collection).map { .set($0) }
            + contentManager.pages(inCollection: collection).map { .page($0) }
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
                    // Distinct identity-only tag — without it the Set row inherits
                    // this collection's `.tag` and selecting either highlights both
                    // (the v0.4.1 bleed bug). `.set` never resolves to a selection;
                    // the SidebarRow inside PageSetRow is additionally
                    // `.selectionDisabled` so clicks/arrow keys skip it.
                    .tag(SelectionTag.set(set.id))
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
            SidebarRow(
                id: collection.id,
                title: collection.title,
                symbol: "folder",
                tag: .collection(collection.id),
                selection: $selection,
                editingID: $editingID,
                justCreatedID: $justCreatedID,
                onRename: { try await vaultManager.renamePageCollection(collection, to: $0) }
            ) {
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
        .listRowBackground(
            SelectionChrome(
                isSelected: SelectionTag.collection(collection.id).matches(selection)
            )
        )
        // Load on row appearance so Pages are available even when collapsed.
        .task {
            await contentManager.loadAll(forCollection: collection)
        }
    }

    /// Stub-and-edit "New Page in This Collection" trigger.
    private func createPage() {
        guard !isCreatingPage else { return }
        isCreatingPage = true
        let existing = contentManager.pages(inCollection: collection).map(\.title)
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

    /// Stub-and-edit "New Set" trigger.
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

    /// Routes a drag-reorder to the correct manager — two-zone offset
    /// translation, one level down from PageTypeRow.reorder. Cross-zone drags
    /// (a Set into the pages zone, or vice versa) are silently rejected.
    private func reorder(fromOffsets source: IndexSet, toOffset destination: Int) {
        let items = disclosureItems
        let setCount = pageSetManager.pageSets(in: collection).count

        let allSets = source.allSatisfy { $0 < setCount }
        let allPages = source.allSatisfy { $0 >= setCount }

        guard allSets || allPages else { return }  // cross-zone drag — reject

        withAnimation(.snappy) {
            if allSets {
                let clampedDestination = min(destination, setCount)
                pageSetManager.reorderPageSets(
                    in: collection,
                    fromOffsets: source,
                    toOffset: clampedDestination
                )
            } else {
                let localSource = IndexSet(source.map { $0 - setCount })
                let pageCount = items.count - setCount
                let rawLocal = destination - setCount
                let localDestination = min(max(rawLocal, 0), pageCount)
                contentManager.reorderPages(
                    inCollection: collection,
                    fromOffsets: localSource,
                    toOffset: localDestination
                )
            }
        }
    }
}
