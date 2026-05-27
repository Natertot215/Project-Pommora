import SwiftUI

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
    @Environment(SettingsManager.self) private var settingsManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool
    @State private var expanded: Bool = false
    @State private var isCreatingPage: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(contentManager.pages(in: collection)) { page in
                PageRow(
                    page: page,
                    parent: .collection(collection, vault: parentVault),
                    selection: $selection,
                    editingID: $editingID,
                    justCreatedID: $justCreatedID
                )
                .tag(SelectionTag.page(page.id))
            }
            .onMove { source, destination in
                withAnimation(.snappy) {
                    contentManager.reorderPages(
                        in: collection, fromOffsets: source, toOffset: destination
                    )
                }
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
                let collectionLabel = settingsManager.settings.labels.pageCollection.singular
                Button("New Page (in This \(collectionLabel))") { createPage() }
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
}
