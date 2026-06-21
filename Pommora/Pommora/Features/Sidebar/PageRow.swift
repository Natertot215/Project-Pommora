import SwiftUI

/// Leaf sidebar row for a Page (`.md`) sitting either directly in a Page Type
/// root or inside a Page Collection sub-folder. Parent routing goes through
/// `PageParent` so the row is unaware of which `PageContentManager` overload is
/// being called.
struct PageRow: View {
    let page: PageMeta
    let parent: PageParent
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?

    @Environment(PageContentManager.self) private var contentManager

    /// The page's icon, falling back to the default page glyph. A custom icon
    /// (set in the header or sidebar picker) overrides; empty/nil shows the
    /// default. Re-reads `page.frontmatter.icon` so sidebar rows reflect icon
    /// changes live once the manager cache refreshes.
    private var rowSymbol: String {
        page.frontmatter.icon.nonEmpty ?? "doc.text"
    }

    var body: some View {
        SidebarRow(
            id: page.id,
            title: page.title,
            symbol: rowSymbol,
            tag: .page(page.id),
            selection: $selection,
            editingID: $editingID,
            justCreatedID: $justCreatedID,
            onRename: { newTitle in
                // Resolve the parent-specific manager overload; the row stays
                // unaware of which PageContentManager rename is dispatched.
                switch parent {
                case .collection(let coll, let vault):
                    try await contentManager.renamePage(page, to: newTitle, in: coll, vault: vault)
                case .set(let set, let coll, let vault):
                    try await contentManager.renamePage(page, to: newTitle, in: set, collection: coll, vault: vault)
                case .vaultRoot(let vault):
                    try await contentManager.renamePage(page, to: newTitle, inVaultRoot: vault)
                }
            }
        ) {
            Button("Edit Title") { editingID = page.id }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete() }
            }
        }
        .listRowBackground(
            SelectionChrome(isSelected: SelectionTag.page(page.id).matches(selection))
        )
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
