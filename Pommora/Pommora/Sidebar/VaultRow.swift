import SwiftUI

struct VaultRow: View {
    let vault: Vault
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @State private var expanded: Bool = false

    @Environment(VaultManager.self) private var vaultManager
    @Environment(ContentManager.self) private var contentManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            // Vault-root Pages render ABOVE Collections per spec
            // (Vaults.md:112-114). PageRow is a leaf — not selectable in v0.2.
            ForEach(contentManager.pages(in: vault)) { page in
                PageRow(
                    page: page,
                    parent: .vaultRoot(vault),
                    editingID: $editingID
                )
            }
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
        .listRowBackground(
            SelectionChrome(
                isSelected: SelectionTag.vault(vault.id).matches(selection)
            )
        )
        // Load vault-root Pages/Items when the row appears, regardless of
        // disclosure state. `.task` fires once on appearance; if it were
        // attached to the disclosure children it would only fire on expand.
        .task {
            await contentManager.loadAll(for: vault)
        }
    }

    @ViewBuilder
    private var label: some View {
        if editingID == vault.id {
            renamingRow
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

    private var renamingRow: some View {
        HStack(spacing: 8) {
            Image(systemName: vault.icon ?? "tray.2")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 16, height: 16, alignment: .center)
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .focused($renameFocused)
                .onSubmit { commit() }
                .onKeyPress(.escape) { cancel(); return .handled }
                .onChange(of: renameFocused) { _, focused in
                    if !focused && !isCommitting && editingID == vault.id {
                        cancel()
                    }
                }
                .onAppear {
                    draft = vault.title
                    renameFocused = true
                }
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
        .padding(.trailing, 0)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commit() {
        guard draft != vault.title else { editingID = nil; return }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await vaultManager.renameVault(vault, to: draft)
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
}
