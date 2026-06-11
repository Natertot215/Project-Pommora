import SwiftUI

/// Sidebar row for a PageSet — a disclosure of its member Pages, one level
/// below PageCollectionRow and modeled on it. Sets are non-selectable: the
/// call site (PageCollectionRow) tags the whole row with the identity-only
/// `SelectionTag.set` (never matches, never resolves), the label row is
/// `.selectionDisabled` so clicks and keyboard traversal skip it, and there
/// is NO SelectionChrome. Only the PageRow children carry selectable tags.
/// `.selectionDisabled` is applied to the LABEL, not the DisclosureGroup —
/// row traits on a multi-row container propagate to the generated child rows
/// (the same inheritance that caused the tag-bleed bug), which would disable
/// the Pages inside.
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
    @Environment(PageTypeManager.self) private var vaultManager

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
                .selectionDisabled(true)
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
                Menu("Move to…") {
                    ForEach(vaultManager.types) { vault in
                        ForEach(vaultManager.pageCollections(in: vault)) { collection in
                            Button("\(vault.title) › \(collection.title)") {
                                moveTo(collection, vault: vault)
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

    /// Plain-value helper for the move menu's `disabled` check — kept out of
    /// the @ViewBuilder closure per quirk #12 (GRDB String overload pollution).
    private func isCurrentCollection(_ collection: PageCollection) -> Bool {
        collection.id == parentCollection.id
    }

    /// Whole-Set move. Same-vault targets move immediately (strip-free — one
    /// schema). A cross-vault target first counts the property values the
    /// move would strip: non-zero routes through the sidebar confirmation
    /// dialog; zero proceeds directly.
    private func moveTo(_ collection: PageCollection, vault: PageType) {
        Task {
            do {
                if vault.id != parentVault.id {
                    let stripCount = try await pageSetManager.moveStripTotal(
                        for: set, from: parentVault, to: vault)
                    if stripCount > 0 {
                        confirmingDelete = .moveSet(
                            set, destination: collection, destinationVault: vault,
                            sourceVault: parentVault, stripCount: stripCount)
                        return
                    }
                }
                try await pageSetManager.moveSet(
                    set, to: collection, destinationVault: vault,
                    sourceVault: parentVault, contentManager: contentManager)
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
