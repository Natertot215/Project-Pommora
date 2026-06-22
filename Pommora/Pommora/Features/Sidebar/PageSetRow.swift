import SwiftUI

/// Sidebar row for a PageSet — a disclosure of its member Pages. Sets are
/// non-selectable: the header passes `tag: nil` and is `.selectionDisabled`, and
/// there is NO SelectionChrome (the call site PageCollectionRow tags the row).
/// `.selectionDisabled` goes on the LABEL (the `SidebarRow`), NOT the
/// DisclosureGroup — row traits on a multi-row container propagate to the
/// generated child rows, which would disable the Pages inside.
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
            .selectionDisabled(true)
        }
        // Load on row appearance so Pages are available even when collapsed.
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

    /// Plain-value helper for the move menu's `disabled` check — kept out of the
    /// @ViewBuilder closure per quirk #12 (GRDB String overload pollution).
    private func isCurrentCollection(_ collection: PageCollection) -> Bool {
        collection.id == parentCollection.id
    }

    /// Whole-Set move. Same-vault targets move immediately; a cross-vault target
    /// first counts the property values the move would strip — non-zero routes
    /// through the confirmation dialog, zero proceeds directly.
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
}
