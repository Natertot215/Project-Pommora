import SwiftUI

struct VaultRow: View {
    let vault: Vault
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @State private var expanded: Bool = false

    @Environment(VaultManager.self) private var vaultManager

    @State private var draft: String = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(vaultManager.collections(in: vault)) { coll in
                CollectionRow(
                    collection: coll,
                    parentVault: vault,
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
            }
        } label: {
            label
        }
    }

    @ViewBuilder
    private var label: some View {
        if editingID == vault.id {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .focused($renameFocused)
                .onSubmit { commit() }
                .onKeyPress(.escape) { editingID = nil; return .handled }
                .onAppear {
                    draft = vault.title
                    renameFocused = true
                }
        } else {
            SelectableRow(
                title: vault.title,
                symbol: vault.icon ?? "tray.2",
                tag: SelectionTag.vault(vault.id),
                selection: $selection,
                accent: nil,
                onSelect: { selection = .vault(vault) }
            )
            .contextMenu {
                Button("New Vault") { presentedSheet = .newVault }
                Button("New Collection (in This Vault)") { presentedSheet = .newCollection(vault: vault) }
                Button("New Page (in This Vault root)") { presentedSheet = .newPageInVault(vault: vault) }
                Divider()
                Button("Rename") { editingID = vault.id }
                Button("Change Icon") { presentedSheet = .editIcon(.vault(vault)) }
                Divider()
                Button("Delete", role: .destructive) {
                    let cols = vaultManager.collections(in: vault).count
                    confirmingDelete = .deleteVault(vault, collectionCount: cols)
                }
            }
        }
    }

    private func commit() {
        guard draft != vault.title else { editingID = nil; return }
        Task {
            do {
                try await vaultManager.renameVault(vault, to: draft)
                editingID = nil
            } catch {
                // editingID stays set; user can retry
            }
        }
    }
}
