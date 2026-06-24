import SwiftUI

// MARK: - Unified disclosure item

/// Sets and Pages in a single ordered list for the PageCollection disclosure body —
/// Sets render above Pages. Single ForEach + .onMove avoids the dual-ForEach SwiftUI
/// bug where only the first ForEach's .onMove is honoured.
private enum CollectionDisclosureItem: Identifiable {
    case collection(PageSet)
    case page(PageMeta)

    var id: String {
        switch self {
        case .collection(let c): return "c:\(c.id)"
        case .page(let p): return "p:\(p.id)"
        }
    }
}

// MARK: - PageCollectionRow

struct PageCollectionRow: View {
    let pageCollection: PageCollection
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    let nexus: Nexus
    let index: PommoraIndex?
    @State private var expanded: Bool = false

    @Environment(PageCollectionManager.self) private var collectionManager
    @Environment(PageContentManager.self) private var contentManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(SidebarSectionsManager.self) private var sectionsManager

    @State private var showingCollectionSettings: Bool = false
    @State private var isCreatingCollection: Bool = false
    @State private var isCreatingPage: Bool = false

    // Sets first, then PageCollection-root pages — single ForEach + one .onMove
    // (SwiftUI honours only the first sibling ForEach's .onMove in a disclosure).
    private var disclosureItems: [CollectionDisclosureItem] {
        collectionManager.pageCollections(in: pageCollection).map { .collection($0) }
            + contentManager.pages(in: pageCollection).map { .page($0) }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(disclosureItems) { item in
                switch item {
                case .collection(let coll):
                    CollectionSetRow(
                        collection: coll,
                        parentPageCollection: pageCollection,
                        selection: $selection,
                        editingID: $editingID,
                        justCreatedID: $justCreatedID,
                        presentedSheet: $presentedSheet,
                        confirmingDelete: $confirmingDelete
                    )
                    .tag(SelectionTag.collection(coll.id))
                case .page(let page):
                    PageRow(
                        page: page,
                        parent: .collectionRoot(pageCollection),
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
                id: pageCollection.id,
                title: pageCollection.title,
                symbol: pageCollection.icon ?? "tray.2",
                tag: .pageCollection(pageCollection.id),
                selection: $selection,
                editingID: $editingID,
                justCreatedID: $justCreatedID,
                onRename: { try await collectionManager.renamePageCollection(pageCollection, to: $0) }
            ) {
                let pageCollectionLabel = settingsManager.settings.labels.pageCollection.singular
                let setLabel = settingsManager.settings.labels.pageSet.singular
                // Top-tier PageCollection creation is NOT offered here — only via the
                // "+" in the Pages section header. This menu creates children (Sets + Pages) only.
                Button("New \(setLabel)") { createPageCollection() }
                    .disabled(isCreatingCollection)
                Button("New Page") { createPage() }
                    .disabled(isCreatingPage)
                // Hidden until at least one user section exists.
                if !sectionsManager.config.sections.isEmpty {
                    Divider()
                    Menu("Move to Section") {
                        ForEach(sectionsManager.config.sections) { target in
                            Button(target.label) { moveToSection(target.id) }
                                .disabled(isInSection(target.id))
                        }
                        if currentSectionID != nil {
                            Divider()
                            Button("Remove from Section") { removeFromSection() }
                        }
                    }
                }
                Divider()
                Button("\(pageCollectionLabel) Settings…") {
                    showingCollectionSettings = true
                }
                Divider()
                Button("Edit Title") { editingID = pageCollection.id }
                Button("Edit Icon") { presentedSheet = .editIcon(.pageCollection(pageCollection)) }
                Divider()
                Button("Delete", role: .destructive) {
                    let cols = collectionManager.pageCollections(in: pageCollection).count
                    confirmingDelete = .deletePageCollection(pageCollection, collectionCount: cols)
                }
            }
        }
        .listRowBackground(
            SelectionChrome(
                isSelected: SelectionTag.pageCollection(pageCollection.id).matches(selection)
            )
        )
        .task {
            await contentManager.loadAll(for: pageCollection)
        }
        .sheet(isPresented: $showingCollectionSettings) {
            CollectionSettingsSheet(
                pageCollection: pageCollection,
                collectionManager: collectionManager,
                nexus: nexus,
                index: index,
                onDismiss: { showingCollectionSettings = false }
            )
            .interactiveDismissDisabled()
        }
    }

    /// Stub-and-edit "New Page" trigger — creates a Page at the PageCollection root.
    private func createPage() {
        guard !isCreatingPage else { return }
        isCreatingPage = true
        let existing = contentManager.pages(in: pageCollection).map(\.title)
        let title = DefaultTitleResolver.resolve(label: "Page", existingTitles: existing)
        Task {
            defer { isCreatingPage = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await contentManager.createPage(name: title, inCollectionRoot: pageCollection)
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
    private func createPageCollection() {
        guard !isCreatingCollection else { return }
        isCreatingCollection = true
        let label = settingsManager.settings.labels.pageSet.singular
        let existing = collectionManager.pageCollections(in: pageCollection).map(\.title)
        let title = DefaultTitleResolver.resolve(label: label, existingTitles: existing)
        Task {
            defer { isCreatingCollection = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await collectionManager.createPageCollection(
                            name: title, inPageCollection: pageCollection
                        )
                    },
                    onCreate: { newCollection in
                        editingID = newCollection.id
                        justCreatedID = newCollection.id
                    }
                )
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    // MARK: - User collection sections

    /// The user section currently holding this collection, if any (single-membership).
    private var currentSectionID: String? {
        sectionsManager.section(containing: pageCollection.id)?.id
    }

    /// Plain-value helper for the context-menu `disabled` check — kept out of @ViewBuilder
    /// per quirk #9 (GRDB String overload pollution).
    private func isInSection(_ sectionID: String) -> Bool {
        currentSectionID == sectionID
    }

    /// Single-membership section move (navigation-only — the folder never moves on disk).
    private func moveToSection(_ sectionID: String) {
        Task {
            do {
                try await sectionsManager.moveCollection(id: pageCollection.id, toSection: sectionID)
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    private func removeFromSection() {
        Task {
            do {
                try await sectionsManager.removeCollectionFromSections(id: pageCollection.id)
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    /// Routes a drag-reorder to the correct manager. Cross-set drags (a
    /// collection into the pages zone, or vice versa) are silently rejected;
    /// same-set drags are translated back to per-set offsets before forwarding.
    private func reorder(fromOffsets source: IndexSet, toOffset destination: Int) {
        let items = disclosureItems
        let collectionCount = collectionManager.pageCollections(in: pageCollection).count

        let allCollections = source.allSatisfy { $0 < collectionCount }
        let allPages = source.allSatisfy { $0 >= collectionCount }

        guard allCollections || allPages else { return }  // cross-set drag — reject

        withAnimation(.snappy) {
            if allCollections {
                let clampedDestination = min(destination, collectionCount)
                collectionManager.reorderPageCollections(
                    in: pageCollection,
                    fromOffsets: source,
                    toOffset: clampedDestination
                )
            } else {
                let localSource = IndexSet(source.map { $0 - collectionCount })
                let pageCount = items.count - collectionCount
                let rawLocal = destination - collectionCount
                let localDestination = min(max(rawLocal, 0), pageCount)
                contentManager.reorderPages(
                    inCollectionRoot: pageCollection,
                    fromOffsets: localSource,
                    toOffset: localDestination
                )
            }
        }
    }
}
