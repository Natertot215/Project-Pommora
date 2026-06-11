import SwiftUI

/// Sidebar row for a PageSet — a disclosure of its member Pages, one level
/// below PageCollectionRow and modeled on it. Sets are non-selectable: the
/// label carries NO `.tag()` and NO SelectionChrome (untagged rows are
/// natively non-selectable in `List(selection:)`); only the PageRow children
/// are tagged.
struct PageSetRow: View {
    let set: PageSet
    let parentCollection: PageCollection
    let parentVault: PageType
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @Environment(PageSetManager.self) private var pageSetManager
    @Environment(PageContentManager.self) private var contentManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool
    @State private var expanded: Bool = false
    @State private var isCreatingPage: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(contentManager.pages(in: set)) { page in
                PageRow(
                    page: page,
                    parent: .set(set, collection: parentCollection, vault: parentVault),
                    selection: $selection,
                    editingID: $editingID,
                    justCreatedID: $justCreatedID
                )
                .tag(SelectionTag.page(page.id))
            }
            .onMove { source, destination in
                withAnimation(.snappy) {
                    contentManager.reorderPages(
                        in: set, fromOffsets: source, toOffset: destination
                    )
                }
            }
        } label: {
            label
        }
        // Same pattern as PageCollectionRow: load on row appearance so Pages
        // are available even when the disclosure is collapsed.
        .task {
            await contentManager.loadAll(for: set)
        }
    }

    @ViewBuilder
    private var label: some View {
        if editingID == set.id {
            RenameableRow(
                symbol: set.icon ?? "folder",
                initialTitle: set.title,
                draft: $draft,
                renameFocused: $renameFocused,
                onSubmit: { commit() },
                onCancel: { cancel() },
                onFocusLoss: {
                    if !isCommitting && editingID == set.id {
                        cancel()
                    }
                },
                selectAllOnAppear: justCreatedID == set.id
            )
        } else {
            SelectableRow(
                title: set.title,
                symbol: set.icon ?? "folder",
                tag: nil,  // Sets are non-selectable — content only, never highlighted.
                selection: $selection,
                accent: nil
            )
            .contextMenu {
                Button("New Page") { createPage() }
                    .disabled(isCreatingPage)
                Divider()
                Button("Edit Title") { editingID = set.id }
                Button("Edit Icon") { presentedSheet = .editIcon(.pageSet(set)) }
                Divider()
                Button("Delete", role: .destructive) {
                    confirmingDelete = .deleteSet(set)
                }
            }
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
                            name: title, in: set, collection: parentCollection, vault: parentVault
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
        guard draft != set.title else {
            editingID = nil
            justCreatedID = nil
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await pageSetManager.renamePageSet(set, to: draft)
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
