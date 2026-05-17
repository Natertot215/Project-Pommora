import SwiftUI

struct CollectionRow: View {
    let collection: Pommora.Collection
    let parentVault: Vault
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var confirmingDelete: SidebarConfirmation?

    @Environment(VaultManager.self) private var vaultManager

    @State private var draft: String = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        Group {
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
                    Button("Rename") { editingID = collection.id }
                    Divider()
                    Button("Delete", role: .destructive) {
                        confirmingDelete = .deleteCollection(collection)
                    }
                }
            }
        }
    }

    private func commit() {
        guard draft != collection.title else { editingID = nil; return }
        Task {
            do { try await vaultManager.renameCollection(collection, to: draft) } catch {}
            editingID = nil
        }
    }
}
