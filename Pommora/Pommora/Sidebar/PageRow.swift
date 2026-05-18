import SwiftUI

/// Leaf sidebar row for a Page (`.md`) sitting either directly in a Vault's
/// root or inside a Collection sub-folder. NOT a `SelectableRow` — Pages aren't
/// selectable in v0.2 (the editor lands in v0.6); the row exists for visibility
/// + rename / delete via the right-click context menu.
///
/// Parent routing (vault-root vs Collection) goes through `PageParent`, so the
/// row itself stays unaware of which ContentManager overload is being called.
struct PageRow: View {
    let page: PageMeta
    let parent: PageParent
    @Binding var editingID: String?

    @Environment(ContentManager.self) private var contentManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        if editingID == page.id {
            renamingRow
        } else {
            leafLabel
                .contextMenu {
                    Button("Rename") { editingID = page.id }
                    Divider()
                    Button("Delete", role: .destructive) {
                        Task { await delete() }
                    }
                }
        }
    }

    // MARK: - Subviews

    private var leafLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 16, height: 16, alignment: .center)
            Text(page.title)
                .foregroundStyle(.primary)
        }
        .padding(.leading, 2)
        .padding(.trailing, 0)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// Mirrors leafLabel's HStack shape (icon stays visible during rename),
    /// only the title slot becomes a TextField.
    private var renamingRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 16, height: 16, alignment: .center)
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .focused($nameFieldFocused)
                .onSubmit { commit() }
                .onKeyPress(.escape) { cancel(); return .handled }
                .onChange(of: nameFieldFocused) { _, focused in
                    if !focused && !isCommitting && editingID == page.id {
                        cancel()
                    }
                }
                .onAppear {
                    draft = page.title
                    nameFieldFocused = true
                }
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
        .padding(.trailing, 0)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func commit() {
        guard draft != page.title else { editingID = nil; return }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                switch parent {
                case .collection(let coll, let vault):
                    try await contentManager.renamePage(page, to: draft, in: coll, vault: vault)
                case .vaultRoot(let vault):
                    try await contentManager.renamePage(page, to: draft, inVaultRoot: vault)
                }
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

    private func delete() async {
        do {
            switch parent {
            case .collection(let coll, _):
                try await contentManager.deletePage(page, in: coll)
            case .vaultRoot(let vault):
                try await contentManager.deletePage(page, inVaultRoot: vault)
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }
}
