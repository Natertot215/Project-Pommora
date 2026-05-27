import SwiftUI

/// Sidebar disclosure row for a Folder — the third tier on the Pages side
/// (PageType → PageCollection → Folder → Page). Structurally identical to
/// `PageCollectionRow` but one level deeper and terminal: a Folder holds
/// Pages only (no nested Folders, no Collections — three-layer cap).
///
/// Children are `PageRow`s routed through `PageParent.folder(_, vault:)`.
/// Selecting the Folder routes to `FolderDetailView` via `SelectionTag.folder`.
/// The per-Folder icon (a divergence from Collections, which use a hardcoded
/// `folder` symbol) renders in both rename + selectable states.
struct FolderRow: View {
    let folder: Folder
    let parentVault: PageType
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var confirmingDelete: SidebarConfirmation?

    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(PageContentManager.self) private var contentManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool
    @State private var expanded: Bool = false
    @State private var isCreatingPage: Bool = false

    private var symbol: String { folder.icon ?? "folder" }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(contentManager.pages(in: folder)) { page in
                PageRow(
                    page: page,
                    parent: .folder(folder, vault: parentVault),
                    selection: $selection,
                    editingID: $editingID,
                    justCreatedID: $justCreatedID
                )
                .tag(SelectionTag.page(page.id))
            }
            .onMove { source, destination in
                withAnimation(.snappy) {
                    contentManager.reorderPages(
                        in: folder, fromOffsets: source, toOffset: destination
                    )
                }
            }
        } label: {
            label
        }
        .listRowBackground(
            SelectionChrome(
                isSelected: SelectionTag.folder(folder.id).matches(selection)
            )
        )
        .task {
            await contentManager.loadAll(for: folder)
        }
    }

    @ViewBuilder
    private var label: some View {
        if editingID == folder.id {
            RenameableRow(
                symbol: symbol,
                initialTitle: folder.title,
                draft: $draft,
                renameFocused: $renameFocused,
                onSubmit: { commit() },
                onCancel: { cancel() },
                onFocusLoss: {
                    if !isCommitting && editingID == folder.id {
                        cancel()
                    }
                },
                selectAllOnAppear: justCreatedID == folder.id
            )
        } else {
            SelectableRow(
                title: folder.title,
                symbol: symbol,
                tag: SelectionTag.folder(folder.id),
                selection: $selection,
                accent: nil
            )
            .contextMenu {
                // Three-layer cap enforced at the UI: a Folder only offers
                // "New Page" — never "New Folder" or "New Collection".
                Button("New Page") { createPage() }
                    .disabled(isCreatingPage)
                Divider()
                Button("Rename") { editingID = folder.id }
                Divider()
                Button("Delete", role: .destructive) {
                    confirmingDelete = .deleteFolder(folder)
                }
            }
        }
    }

    /// Stub-and-edit "New Page in This Folder" trigger. Mirrors the
    /// Collection-scoped + Type-root variants — creates a uniquely-named
    /// Page inside the Folder, then flips its sidebar row into rename mode.
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
                            name: title, in: folder, vault: parentVault
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
        guard draft != folder.title else {
            editingID = nil
            justCreatedID = nil
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await vaultManager.renameFolder(folder, to: draft)
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
}
