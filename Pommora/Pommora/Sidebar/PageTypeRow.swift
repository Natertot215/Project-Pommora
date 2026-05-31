import SwiftUI

// MARK: - Unified disclosure item

/// Combines PageCollections and Pages into a single ordered list for the
/// PageType disclosure body. Collections render ABOVE Pages (Nathan's directive
/// 2026-05-25). A single ForEach + .onMove handles both, avoiding the
/// dual-ForEach SwiftUI bug where only the first ForEach's .onMove binding
/// is honoured.
private enum VaultDisclosureItem: Identifiable {
    case collection(PageCollection)
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

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool
    @State private var showingVaultSettings: Bool = false
    @State private var isCreatingCollection: Bool = false
    @State private var isCreatingPage: Bool = false

    // Collections first, then vault-root pages. A single ForEach with one
    // .onMove works around the SwiftUI bug where only the first sibling
    // ForEach's .onMove is honoured inside a DisclosureGroup body.
    private var disclosureItems: [VaultDisclosureItem] {
        pageTypeManager.pageCollections(in: pageType).map { .collection($0) }
            + contentManager.pages(in: pageType).map { .page($0) }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            // Collections render ABOVE Pages per Nathan's directive 2026-05-25.
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
            label
        }
        .listRowBackground(
            SelectionChrome(
                isSelected: SelectionTag.pageType(pageType.id).matches(selection)
            )
        )
        // Load Page-Type-root Pages when the row appears, regardless of
        // disclosure state. `.task` fires once on appearance; if it were
        // attached to the disclosure children it would only fire on expand.
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

    @ViewBuilder
    private var label: some View {
        if editingID == pageType.id {
            RenameableRow(
                symbol: pageType.icon ?? "tray.2",
                initialTitle: pageType.title,
                draft: $draft,
                renameFocused: $renameFocused,
                onSubmit: { commit() },
                onCancel: { cancel() },
                onFocusLoss: {
                    if !isCommitting && editingID == pageType.id {
                        cancel()
                    }
                },
                selectAllOnAppear: justCreatedID == pageType.id
            )
        } else {
            SelectableRow(
                title: pageType.title,
                symbol: pageType.icon ?? "tray.2",
                tag: SelectionTag.pageType(pageType.id),
                selection: $selection,
                accent: nil
            )
            .contextMenu {
                let pageTypeLabel = settingsManager.settings.labels.pageType.singular
                let collectionLabel = settingsManager.settings.labels.pageCollection.singular
                // Vault creation is intentionally NOT offered here — the only
                // way to create a Vault is the "+" button in the Pages section
                // header (SidebarView.createPageType). A Vault's context menu
                // creates its children (Collections + Pages) only.
                Button("New \(collectionLabel)") { createPageCollection() }
                    .disabled(isCreatingCollection)
                Button("New Page") { createPage() }
                    .disabled(isCreatingPage)
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
    }

    /// Stub-and-edit "New Page" trigger. Creates a uniquely-named Page at
    /// the PageType folder root (no PageCollection parent), then flips the
    /// matching sidebar row into rename mode with the default title
    /// pre-selected. `isCreatingPage` guards against rapid double-clicks
    /// producing collision toasts. Mirrors `PageTypeDetailView.createPage()`.
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

    /// Stub-and-edit "New PageCollection" trigger. Creates a uniquely-named
    /// PageCollection on disk + in memory + in SQLite, then flips the
    /// matching sidebar row into rename mode with the default title
    /// pre-selected for replacement. `isCreatingCollection` guards against
    /// rapid double-clicks producing collision toasts.
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

    private func commit() {
        guard draft != pageType.title else {
            editingID = nil
            justCreatedID = nil
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await pageTypeManager.renamePageType(pageType, to: draft)
                editingID = nil
                justCreatedID = nil
            } catch {
                // pendingError set by manager; toast surfaces.
                // editingID preserved on failure for retry — justCreatedID
                // also preserved so the still-visible TextField stays in its
                // select-all state for the next keystroke.
            }
        }
    }

    private func cancel() {
        editingID = nil
        justCreatedID = nil
    }

    /// Routes a drag-reorder to the correct manager.
    ///
    /// Cross-set drags (a collection dragged into the pages zone, or vice
    /// versa) are silently rejected — v0.3.0 doesn't support interleaving.
    /// Same-set drags are translated back to per-set offsets before
    /// forwarding to the manager.
    private func reorder(fromOffsets source: IndexSet, toOffset destination: Int) {
        let items = disclosureItems
        let collectionCount = pageTypeManager.pageCollections(in: pageType).count

        // Determine which set all source indices belong to.
        let allCollections = source.allSatisfy { $0 < collectionCount }
        let allPages = source.allSatisfy { $0 >= collectionCount }

        guard allCollections || allPages else { return }   // cross-set drag — reject

        withAnimation(.snappy) {
            if allCollections {
                // Clamp destination to the collections zone (indices 0..<collectionCount).
                let clampedDestination = min(destination, collectionCount)
                pageTypeManager.reorderPageCollections(
                    in: pageType,
                    fromOffsets: source,
                    toOffset: clampedDestination
                )
            } else {
                // Translate unified-list offsets to page-local offsets.
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
