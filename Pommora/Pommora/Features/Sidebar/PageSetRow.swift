import SwiftUI

// MARK: - Unified disclosure item

private enum SetDisclosureItem: Identifiable {
    case set(PageSet)
    case page(PageMeta)

    var id: String {
        switch self {
        case .set(let s): return "s:\(s.id)"
        case .page(let p): return "p:\(p.id)"
        }
    }
}

// MARK: - PageSetRow

/// Sidebar row for a PageSet — a disclosure of its member Sets (recursively)
/// and Pages. Sets are non-selectable: the header passes `tag: nil` and is
/// `.selectionDisabled`, and there is NO SelectionChrome (the call site tags
/// the row). `.selectionDisabled` goes on the LABEL (the `SidebarRow`), NOT the
/// DisclosureGroup — row traits on a multi-row container propagate to the
/// generated child rows, which would disable the Pages inside.
struct PageSetRow: View {
    let set: PageSet
    let parentCollection: PageSet
    let parentPageCollection: PageCollection
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @Environment(PageSetManager.self) private var pageSetManager
    @Environment(PageContentManager.self) private var contentManager
    @Environment(PageCollectionManager.self) private var collectionManager

    @State private var expanded: Bool = false
    @State private var isCreatingPage: Bool = false

    private var disclosureItems: [SetDisclosureItem] {
        pageSetManager.pageSets(in: set).map { .set($0) }
            + contentManager.pages(in: set).map { .page($0) }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(disclosureItems) { item in
                switch item {
                case .set(let childSet):
                    PageSetRow(
                        set: childSet,
                        parentCollection: parentCollection,
                        parentPageCollection: parentPageCollection,
                        selection: $selection,
                        editingID: $editingID,
                        justCreatedID: $justCreatedID,
                        presentedSheet: $presentedSheet,
                        confirmingDelete: $confirmingDelete
                    )
                    .tag(SelectionTag.set(childSet.id))
                case .page(let page):
                    PageRow(
                        page: page,
                        parent: .set(set, collection: parentCollection, pageCollection: parentPageCollection),
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
                id: set.id,
                title: set.title,
                symbol: set.icon ?? "folder",
                tag: nil,  // Sets are non-selectable — content only, never highlighted.
                selection: $selection,
                editingID: $editingID,
                justCreatedID: $justCreatedID,
                onRename: { try await pageSetManager.renamePageSet(set, to: $0) }
            ) {
                Button("New Page") { createPage() }
                    .disabled(isCreatingPage)
                Divider()
                Button("Edit Title") { editingID = set.id }
                Button("Edit Icon") { presentedSheet = .editIcon(.pageSet(set)) }
                Divider()
                Menu("Move to…") {
                    ForEach(collectionManager.types) { pageCollection in
                        ForEach(collectionManager.pageCollections(in: pageCollection)) { collection in
                            Button("\(pageCollection.title) › \(collection.title)") {
                                moveTo(collection, pageCollection: pageCollection)
                            }
                            .disabled(isCurrentCollection(collection))
                        }
                    }
                }
                Divider()
                Button("Delete", role: .destructive) {
                    confirmingDelete = .deleteSet(set)
                }
            }
            .selectionDisabled(true)
        }
        .task {
            await contentManager.loadAll(for: set)
        }
    }

    /// Stub-and-edit "New Page in This Set" trigger.
    private func createPage() {
        guard !isCreatingPage else { return }
        isCreatingPage = true
        let existing = contentManager.pages(in: set).map(\.title)
        let title = DefaultTitleResolver.resolve(label: "Page", existingTitles: existing)
        Task {
            defer { isCreatingPage = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await contentManager.createPage(
                            name: title, in: set, collection: parentCollection, pageCollection: parentPageCollection
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

    /// Kept out of @ViewBuilder per quirk #12 (GRDB String overload pollution).
    private func isCurrentCollection(_ collection: PageSet) -> Bool {
        collection.id == parentCollection.id
    }

    /// Routes a drag-reorder within this Set: child Sets reorder above, Pages
    /// below. Cross-zone drags are silently rejected.
    private func reorder(fromOffsets source: IndexSet, toOffset destination: Int) {
        let items = disclosureItems
        let setCount = pageSetManager.pageSets(in: set).count

        let allSets = source.allSatisfy { $0 < setCount }
        let allPages = source.allSatisfy { $0 >= setCount }
        guard allSets || allPages else { return }

        withAnimation(.snappy) {
            if allSets {
                pageSetManager.reorderPageSets(
                    in: set, fromOffsets: source,
                    toOffset: min(destination, setCount)
                )
            } else {
                let pageCount = items.count - setCount
                let localSource = IndexSet(source.map { $0 - setCount })
                let localDest = min(max(destination - setCount, 0), pageCount)
                contentManager.reorderPages(in: set, fromOffsets: localSource, toOffset: localDest)
            }
        }
    }

    /// Whole-Set move. Same-collection targets move immediately; a cross-collection target
    /// first counts the property values the move would strip — non-zero routes
    /// through the confirmation dialog, zero proceeds directly.
    private func moveTo(_ collection: PageSet, pageCollection: PageCollection) {
        Task {
            do {
                if pageCollection.id != parentPageCollection.id {
                    let stripCount = try await pageSetManager.moveStripTotal(
                        for: set, from: parentPageCollection, to: pageCollection)
                    if stripCount > 0 {
                        confirmingDelete = .moveSet(
                            set, destination: collection, destinationPageCollection: pageCollection,
                            sourcePageCollection: parentPageCollection, stripCount: stripCount)
                        return
                    }
                }
                try await pageSetManager.moveSet(
                    set, to: collection, destinationPageCollection: pageCollection,
                    sourcePageCollection: parentPageCollection, contentManager: contentManager)
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }
}
