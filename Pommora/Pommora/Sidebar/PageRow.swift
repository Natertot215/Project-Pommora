import SwiftUI

/// Leaf sidebar row for a Page (`.md`) sitting either directly in a Page Type
/// root or inside a Page Collection sub-folder. Owns its own
/// `.listRowBackground` so it doesn't inherit SelectionChrome from the
/// enclosing DisclosureGroup. Parent routing goes through `PageParent` so the
/// row is unaware of which PageContentManager overload is being called.
struct PageRow: View {
    let page: PageMeta
    let parent: PageParent
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?

    @Environment(PageContentManager.self) private var contentManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool

    var body: some View {
        Group {
            if editingID == page.id {
                RenameableRow(
                    symbol: "doc.text",
                    initialTitle: page.title,
                    draft: $draft,
                    renameFocused: $renameFocused,
                    onSubmit: { commit() },
                    onCancel: { cancel() },
                    onFocusLoss: {
                        if !isCommitting && editingID == page.id {
                            cancel()
                        }
                    },
                    selectAllOnAppear: justCreatedID == page.id
                )
            } else {
                SelectableRow(
                    title: page.title,
                    symbol: "doc.text",
                    tag: SelectionTag.page(page.id),
                    selection: $selection,
                    accent: nil
                )
                .contextMenu {
                    Button("Rename") { editingID = page.id }
                    Divider()
                    Button("Delete", role: .destructive) {
                        Task { await delete() }
                    }
                }
            }
        }
        .listRowBackground(
            SelectionChrome(isSelected: SelectionTag.page(page.id).matches(selection))
        )
    }

    // MARK: - Actions

    private func commit() {
        guard draft != page.title else {
            editingID = nil
            justCreatedID = nil
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                switch parent {
                case .collection(let coll, let vault):
                    try await contentManager.renamePage(page, to: draft, in: coll, vault: vault)
                case .folder(let folder, let vault):
                    try await contentManager.renamePage(page, to: draft, in: folder, vault: vault)
                case .vaultRoot(let vault):
                    try await contentManager.renamePage(page, to: draft, inVaultRoot: vault)
                }
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

    private func delete() async {
        do {
            switch parent {
            case .collection(let coll, _):
                try await contentManager.deletePage(page, in: coll)
            case .folder(let folder, _):
                try await contentManager.deletePage(page, in: folder)
            case .vaultRoot(let vault):
                try await contentManager.deletePage(page, inVaultRoot: vault)
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }
}
