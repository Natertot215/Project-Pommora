import SwiftUI

/// Leaf sidebar row for a Page (`.md`) sitting either directly in a Vault's
/// root or inside a Collection sub-folder. Selectable; opens a placeholder
/// detail surface until the editor lands in v0.6.
///
/// Owns its own `.listRowBackground` so it doesn't inherit SelectionChrome
/// from the enclosing DisclosureGroup (PageTypeRow/CollectionRow).
///
/// Parent routing (vault-root vs Collection) goes through `PageParent`, so the
/// row itself stays unaware of which PageContentManager overload is being called.
struct PageRow: View {
    let page: PageMeta
    let parent: PageParent
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?

    @Environment(PageContentManager.self) private var contentManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        Group {
            if editingID == page.id {
                renamingRow
            } else {
                SelectableRow(
                    title: page.title,
                    symbol: "doc.text",
                    tag: SelectionTag.page(page.id),
                    selection: $selection,
                    accent: nil,
                    onSelect: { selection = .page(page) }
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
        .reorderable(
            kind: .page,
            id: page.id,
            containerID: parentContainerID,
            isVaultRoot: isVaultRootParent,
            nexusID: contentManager.nexusID,
            symbol: "doc.text",
            title: page.title,
            accent: nil,
            onDrop: { payload, position in
                let arr = siblingPages()
                guard
                    let from = arr.firstIndex(where: { $0.id == payload.id }),
                    let targetIdx = arr.firstIndex(where: { $0.id == page.id })
                else { return }
                let toOffset = position == .above ? targetIdx : targetIdx + 1
                switch parent {
                case .collection(let coll, _):
                    contentManager.reorderPages(
                        in: coll,
                        fromOffsets: IndexSet(integer: from),
                        toOffset: toOffset
                    )
                case .vaultRoot(let vault):
                    contentManager.reorderPages(
                        inVault: vault,
                        fromOffsets: IndexSet(integer: from),
                        toOffset: toOffset
                    )
                }
            }
        )
    }

    // MARK: - Drag helpers

    /// Container ID for the drag payload: parent Collection's ID when the Page
    /// lives inside a Collection, parent PageType's ID for vault-root Pages.
    /// `DragValidator` uses this to keep drops sibling-only (a vault-root Page
    /// can't land on a Collection page even if they share a PageType, because
    /// `isVaultRoot` must also match).
    private var parentContainerID: String {
        switch parent {
        case .collection(let coll, _): return coll.id
        case .vaultRoot(let vault): return vault.id
        }
    }

    private var isVaultRootParent: Bool {
        if case .vaultRoot = parent { return true }
        return false
    }

    private func siblingPages() -> [PageMeta] {
        switch parent {
        case .collection(let coll, _): return contentManager.pages(in: coll)
        case .vaultRoot(let vault): return contentManager.pages(in: vault)
        }
    }

    // MARK: - Subviews

    /// Mirrors SelectableRow's HStack shape (icon stays visible during rename),
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
                .onKeyPress(.escape) {
                    cancel()
                    return .handled
                }
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
        guard draft != page.title else {
            editingID = nil
            return
        }
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
