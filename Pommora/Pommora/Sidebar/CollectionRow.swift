import SwiftUI

struct CollectionRow: View {
    let collection: Pommora.Collection
    let parentVault: Vault
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @Environment(VaultManager.self) private var vaultManager
    @Environment(ContentManager.self) private var contentManager

    @State private var draft: String = ""
    @FocusState private var renameFocused: Bool
    @State private var expanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(contentManager.pages(in: collection)) { page in
                PageRow(
                    page: page,
                    parent: .collection(collection, vault: parentVault),
                    editingID: $editingID,
                    confirmingDelete: $confirmingDelete
                )
            }
        } label: {
            label
        }
        // Same pattern as VaultRow: load on row appearance so Pages are
        // available even when the disclosure is collapsed (count badges,
        // future search, etc.).
        .task {
            await contentManager.loadAll(for: collection)
        }
    }

    @ViewBuilder
    private var label: some View {
        if editingID == collection.id {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .focused($renameFocused)
                .onSubmit { commit() }
                .onKeyPress(.escape) { editingID = nil; return .handled }
                .onAppear {
                    draft = collection.title
                    renameFocused = true
                }
        } else {
            SelectableRow(
                title: collection.title,
                symbol: "folder",
                tag: SelectionTag.collection(collection.id),
                selection: $selection,
                accent: nil,
                onSelect: { selection = .collection(collection) }
            )
            .contextMenu {
                Button("New Page (in This Collection)") {
                    presentedSheet = .newPage(collection: collection, vault: parentVault)
                }
                Divider()
                Button("Rename") { editingID = collection.id }
                Divider()
                Button("Delete", role: .destructive) {
                    confirmingDelete = .deleteCollection(collection)
                }
            }
        }
    }

    private func commit() {
        guard draft != collection.title else { editingID = nil; return }
        Task {
            do {
                try await vaultManager.renameCollection(collection, to: draft)
                editingID = nil
            } catch {
                // editingID stays set; user can retry
            }
        }
    }
}
