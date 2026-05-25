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
                        presentedSheet: $presentedSheet,
                        confirmingDelete: $confirmingDelete
                    )
                    .tag(SelectionTag.collection(coll.id))
                case .page(let page):
                    PageRow(
                        page: page,
                        parent: .vaultRoot(pageType),
                        selection: $selection,
                        editingID: $editingID
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
                }
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
                Button("New \(pageTypeLabel)") { presentedSheet = .newPageType }
                Button("New \(collectionLabel)") {
                    presentedSheet = .newCollection(pageType: pageType)
                }
                Button("New Page") {
                    presentedSheet = .newPageInPageType(pageType: pageType)
                }
                Divider()
                Button("\(pageTypeLabel) Settings…") {
                    showingVaultSettings = true
                }
                Divider()
                Button("Rename") { editingID = pageType.id }
                Button("Change Icon") { presentedSheet = .editIcon(.pageType(pageType)) }
                Divider()
                Button("Delete", role: .destructive) {
                    let cols = pageTypeManager.pageCollections(in: pageType).count
                    confirmingDelete = .deleteVault(pageType, collectionCount: cols)
                }
            }
        }
    }

    private func commit() {
        guard draft != pageType.title else {
            editingID = nil
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await pageTypeManager.renamePageType(pageType, to: draft)
                editingID = nil
            } catch {
                // pendingError set by manager; toast surfaces.
                // editingID preserved on failure for retry.
            }
        }
    }

    private func cancel() {
        editingID = nil
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
