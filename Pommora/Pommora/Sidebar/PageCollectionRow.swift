import SwiftUI

// MARK: - Unified disclosure item

/// Combines Folders and Collection-root Pages into a single ordered list for
/// the PageCollection disclosure body. Folders render ABOVE Pages (mirrors the
/// Collections-above-Pages rule one tier up at PageTypeRow). A single ForEach +
/// one `.onMove` handles both, avoiding the SwiftUI bug where only the first
/// sibling ForEach's `.onMove` binding is honoured inside a DisclosureGroup,
/// and avoiding the OutlineListCoordinator row-shape-asymmetry crash (quirk #9)
/// — same proven pattern as `VaultDisclosureItem`.
private enum CollectionChildItem: Identifiable {
    case folder(Folder)
    case page(PageMeta)

    var id: String {
        switch self {
        case .folder(let f): return "f:\(f.id)"
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
    @Environment(PageContentManager.self) private var contentManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool
    @State private var expanded: Bool = false
    @State private var isCreatingPage: Bool = false
    @State private var isCreatingFolder: Bool = false

    // Folders first, then Collection-root Pages. A single ForEach with one
    // `.onMove` works around the SwiftUI bug where only the first sibling
    // ForEach's `.onMove` is honoured inside a DisclosureGroup body.
    private var disclosureItems: [CollectionChildItem] {
        vaultManager.folders(in: collection).map { .folder($0) }
            + contentManager.pages(in: collection).map { .page($0) }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(disclosureItems) { item in
                switch item {
                case .folder(let folder):
                    FolderRow(
                        folder: folder,
                        parentVault: parentVault,
                        selection: $selection,
                        editingID: $editingID,
                        justCreatedID: $justCreatedID,
                        confirmingDelete: $confirmingDelete
                    )
                    .tag(SelectionTag.folder(folder.id))
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
        // future search, etc.). Folders come from PageTypeManager.loadAll
        // (run once at launch), so only Pages need a per-row load here.
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
                Button("New Folder") { createFolder() }
                    .disabled(isCreatingFolder)
                Button("New Page") { createPage() }
                    .disabled(isCreatingPage)
                Divider()
                Button("Rename") { editingID = collection.id }
                Divider()
                Button("Delete", role: .destructive) {
                    confirmingDelete = .deleteCollection(collection)
                }
            }
        }
    }

    /// Stub-and-edit "New Folder in This Collection" trigger. Creates a
    /// uniquely-named Folder on disk + in memory + in SQLite, then flips its
    /// sidebar row into rename mode with the default title pre-selected.
    private func createFolder() {
        guard !isCreatingFolder else { return }
        isCreatingFolder = true
        let existing = vaultManager.folders(in: collection).map(\.title)
        let title = DefaultTitleResolver.resolve(label: "Folder", existingTitles: existing)
        Task {
            defer { isCreatingFolder = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await vaultManager.createFolder(in: collection, title: title)
                    },
                    onCreate: { newFolder in
                        editingID = newFolder.id
                        justCreatedID = newFolder.id
                    }
                )
            } catch {
                // pendingError set by manager; toast surfaces.
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

    private func cancel() {
        editingID = nil
        justCreatedID = nil
    }

    /// Routes a drag-reorder to the correct manager. Intra-group only:
    /// Folders reorder among Folders, Pages among Pages — never interleaved.
    /// Cross-group drags (a Folder dragged into the Pages zone, or vice versa)
    /// are silently rejected. Mirrors `PageTypeRow.reorder`.
    private func reorder(fromOffsets source: IndexSet, toOffset destination: Int) {
        let folderCount = vaultManager.folders(in: collection).count

        let allFolders = source.allSatisfy { $0 < folderCount }
        let allPages = source.allSatisfy { $0 >= folderCount }

        guard allFolders || allPages else { return }  // cross-group drag — reject

        withAnimation(.snappy) {
            if allFolders {
                // Clamp destination to the folders zone (indices 0..<folderCount).
                let clampedDestination = min(destination, folderCount)
                vaultManager.reorderFolders(
                    in: collection,
                    fromOffsets: source,
                    toOffset: clampedDestination
                )
            } else {
                // Translate unified-list offsets to page-local offsets.
                let localSource = IndexSet(source.map { $0 - folderCount })
                let pageCount = disclosureItems.count - folderCount
                let rawLocal = destination - folderCount
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
