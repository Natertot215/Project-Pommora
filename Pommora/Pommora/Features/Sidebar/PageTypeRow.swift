import SwiftUI

// MARK: - Unified disclosure item

/// Combines PageCollections and Pages into a single ordered list for the
/// PageType disclosure body. Collections render ABOVE Pages. A single ForEach +
/// .onMove handles both, avoiding the dual-ForEach SwiftUI bug where only the
/// first ForEach's .onMove binding is honoured.
private enum VaultDisclosureItem: Identifiable {
    case collection(PageSet)
    case page(PageMeta)

    var id: String {
        switch self {
        case .collection(let c): return "c:\(c.id)"
        case .page(let p): return "p:\(p.id)"
        }
    }
}

// MARK: - PageTypeRow

struct PageTypeRow: View {
    let pageType: PageType
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    let nexus: Nexus
    let index: PommoraIndex?
    @State private var expanded: Bool = false

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(PageContentManager.self) private var contentManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(SidebarSectionsManager.self) private var sectionsManager

    @State private var showingVaultSettings: Bool = false
    @State private var isCreatingCollection: Bool = false
    @State private var isCreatingPage: Bool = false

    // Collections first, then vault-root pages — single ForEach + one .onMove
    // (SwiftUI honours only the first sibling ForEach's .onMove in a disclosure).
    private var disclosureItems: [VaultDisclosureItem] {
        pageTypeManager.pageCollections(in: pageType).map { .collection($0) }
            + contentManager.pages(in: pageType).map { .page($0) }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(disclosureItems) { item in
                switch item {
                case .collection(let coll):
                    PageCollectionRow(
                        collection: coll,
                        parentVault: pageType,
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
                        parent: .vaultRoot(pageType),
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
                id: pageType.id,
                title: pageType.title,
                symbol: pageType.icon ?? "tray.2",
                tag: .pageType(pageType.id),
                selection: $selection,
                editingID: $editingID,
                justCreatedID: $justCreatedID,
                onRename: { try await pageTypeManager.renamePageType(pageType, to: $0) }
            ) {
                let pageTypeLabel = settingsManager.settings.labels.pageType.singular
                let collectionLabel = settingsManager.settings.labels.pageCollection.singular
                // Vault creation is intentionally NOT offered here — the only way
                // to create a Vault is the "+" in the Pages section header
                // (SidebarView.createPageType). A Vault's menu creates its
                // children (Collections + Pages) only.
                Button("New \(collectionLabel)") { createPageCollection() }
                    .disabled(isCreatingCollection)
                Button("New Page") { createPage() }
                    .disabled(isCreatingPage)
                // User vault sections (PagesV2 P9, navigation-only). Hidden until
                // at least one section exists; "Remove from Section" appears only
                // while this vault is grouped.
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
                Button("\(pageTypeLabel) Settings…") {
                    showingVaultSettings = true
                }
                Divider()
                Button("Edit Title") { editingID = pageType.id }
                Button("Edit Icon") { presentedSheet = .editIcon(.pageType(pageType)) }
                Divider()
                Button("Delete", role: .destructive) {
                    let cols = pageTypeManager.pageCollections(in: pageType).count
                    confirmingDelete = .deleteVault(pageType, collectionCount: cols)
                }
            }
        }
        .listRowBackground(
            SelectionChrome(
                isSelected: SelectionTag.pageType(pageType.id).matches(selection)
            )
        )
        // Load Page-Type-root Pages when the row appears, regardless of disclosure.
        .task {
            await contentManager.loadAll(for: pageType)
        }
        .sheet(isPresented: $showingVaultSettings) {
            VaultSettingsSheet(
                pageType: pageType,
                pageTypeManager: pageTypeManager,
                nexus: nexus,
                index: index,
                onDismiss: { showingVaultSettings = false }
            )
            .interactiveDismissDisabled()
        }
    }

    /// Stub-and-edit "New Page" trigger — creates a Page at the PageType root.
    private func createPage() {
        guard !isCreatingPage else { return }
        isCreatingPage = true
        let existing = contentManager.pages(in: pageType).map(\.title)
        let title = DefaultTitleResolver.resolve(label: "Page", existingTitles: existing)
        Task {
            defer { isCreatingPage = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await contentManager.createPage(name: title, inVaultRoot: pageType)
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

    /// Stub-and-edit "New PageCollection" trigger.
    private func createPageCollection() {
        guard !isCreatingCollection else { return }
        isCreatingCollection = true
        let label = settingsManager.settings.labels.pageCollection.singular
        let existing = pageTypeManager.pageCollections(in: pageType).map(\.title)
        let title = DefaultTitleResolver.resolve(label: label, existingTitles: existing)
        Task {
            defer { isCreatingCollection = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await pageTypeManager.createPageCollection(
                            name: title, inPageType: pageType
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

    // MARK: - User vault sections (PagesV2 P9)

    /// The user section currently holding this vault, if any (single-membership).
    private var currentSectionID: String? {
        sectionsManager.section(containing: pageType.id)?.id
    }

    /// Plain-value helper for the context-menu `disabled` check — kept out of the
    /// @ViewBuilder closure per quirk #9 (GRDB String overload pollution).
    private func isInSection(_ sectionID: String) -> Bool {
        currentSectionID == sectionID
    }

    /// Single-membership move (one manager mutation). Navigation-only — the vault
    /// folder never moves on disk.
    private func moveToSection(_ sectionID: String) {
        Task {
            do {
                try await sectionsManager.moveVault(id: pageType.id, toSection: sectionID)
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    /// Returns the vault to the default Vaults section.
    private func removeFromSection() {
        Task {
            do {
                try await sectionsManager.removeVaultFromSections(id: pageType.id)
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
        let collectionCount = pageTypeManager.pageCollections(in: pageType).count

        let allCollections = source.allSatisfy { $0 < collectionCount }
        let allPages = source.allSatisfy { $0 >= collectionCount }

        guard allCollections || allPages else { return }  // cross-set drag — reject

        withAnimation(.snappy) {
            if allCollections {
                let clampedDestination = min(destination, collectionCount)
                pageTypeManager.reorderPageCollections(
                    in: pageType,
                    fromOffsets: source,
                    toOffset: clampedDestination
                )
            } else {
                let localSource = IndexSet(source.map { $0 - collectionCount })
                let pageCount = items.count - collectionCount
                let rawLocal = destination - collectionCount
                let localDestination = min(max(rawLocal, 0), pageCount)
                contentManager.reorderPages(
                    inVault: pageType,
                    fromOffsets: localSource,
                    toOffset: localDestination
                )
            }
        }
    }
}
