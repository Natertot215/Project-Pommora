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

    @State private var renameState = InlineRenameState()
    @FocusState private var renameFocused: Bool

    /// The page's icon, falling back to the default page glyph. A custom icon
    /// (set in the header or sidebar picker) overrides; empty/nil shows the
    /// default. Re-reads `page.frontmatter.icon` so sidebar rows reflect icon
    /// changes live once the manager cache refreshes.
    private var rowSymbol: String {
        page.frontmatter.icon.nonEmpty ?? "doc.text"
    }

    var body: some View {
        Group {
            if editingID == page.id {
                RenameableRow(
                    symbol: rowSymbol,
                    initialTitle: page.title,
                    draft: $renameState.draft,
                    renameFocused: $renameFocused,
                    onSubmit: { commit() },
                    onCancel: { clearEditing() },
                    onFocusLoss: {
                        if !renameState.isCommitting && editingID == page.id {
                            clearEditing()
                        }
                    },
                    selectAllOnAppear: justCreatedID == page.id
                )
            } else {
                SelectableRow(
                    title: page.title,
                    symbol: rowSymbol,
                    tag: SelectionTag.page(page.id),
                    selection: $selection,
                    accent: nil
                )
                .contextMenu {
                    Button("Edit Title") { editingID = page.id }
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
        renameState.commit(
            currentTitle: page.title,
            rename: {
                // Resolve the parent-specific manager overload; the row stays
                // unaware of which PageContentManager rename is dispatched.
                switch parent {
                case .collection(let coll, let vault):
                    try await contentManager.renamePage(page, to: renameState.draft, in: coll, vault: vault)
                case .set(let set, let coll, let vault):
                    try await contentManager.renamePage(page, to: renameState.draft, in: set, collection: coll, vault: vault)
                case .vaultRoot(let vault):
                    try await contentManager.renamePage(page, to: renameState.draft, inVaultRoot: vault)
                }
            },
            onCommitted: { clearEditing() }
        )
    }

    private func clearEditing() {
        editingID = nil
        justCreatedID = nil
    }

    private func delete() async {
        do {
            switch parent {
            case .collection(let coll, _):
                try await contentManager.deletePage(page, in: coll)
            case .set(let set, _, _):
                try await contentManager.deletePage(page, in: set)
            case .vaultRoot(let vault):
                try await contentManager.deletePage(page, inVaultRoot: vault)
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }
}
