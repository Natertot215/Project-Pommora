import SwiftUI

/// Shared content for every sidebar row: the selectable ↔ inline-rename swap
/// plus the rename plumbing (`InlineRenameState` + focus + commit/cancel/
/// focus-loss) that each row used to repeat verbatim. Callers pass the entity
/// specifics (symbol, title, tag, the rename call) and a context menu.
///
/// Pure content — like `SelectableRow`, it carries NO selection chrome. The
/// caller keeps `.listRowBackground(SelectionChrome(...))` at the row-file level
/// (quirk #9), so the List's row structure is unchanged.
struct SidebarRow<Menu: View>: View {
    let id: String
    let title: String
    let symbol: String
    var symbolForeground: Color = .primary
    /// `nil` for non-selectable rows (e.g. Page Sets) — passed through to
    /// `SelectableRow`, which never highlights a nil tag.
    let tag: SelectionTag?
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    /// The manager rename call for the committed (changed, non-empty) draft.
    let onRename: (_ newTitle: String) async throws -> Void
    @ViewBuilder let menu: () -> Menu

    @State private var renameState = InlineRenameState()
    @FocusState private var renameFocused: Bool

    init(
        id: String,
        title: String,
        symbol: String,
        symbolForeground: Color = .primary,
        tag: SelectionTag?,
        selection: Binding<SidebarSelection>,
        editingID: Binding<String?>,
        justCreatedID: Binding<String?>,
        onRename: @escaping (_ newTitle: String) async throws -> Void,
        @ViewBuilder menu: @escaping () -> Menu
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.symbolForeground = symbolForeground
        self.tag = tag
        self._selection = selection
        self._editingID = editingID
        self._justCreatedID = justCreatedID
        self.onRename = onRename
        self.menu = menu
    }

    var body: some View {
        if editingID == id {
            RenameableRow(
                symbol: symbol,
                symbolForeground: symbolForeground,
                initialTitle: title,
                draft: $renameState.draft,
                renameFocused: $renameFocused,
                onSubmit: { commit() },
                onCancel: { clearEditing() },
                onFocusLoss: {
                    if !renameState.isCommitting && editingID == id { clearEditing() }
                },
                selectAllOnAppear: justCreatedID == id
            )
        } else {
            SelectableRow(
                title: title,
                symbol: symbol,
                tag: tag,
                selection: $selection,
                accent: nil
            )
            .contextMenu { menu() }
        }
    }

    private func commit() {
        renameState.commit(
            currentTitle: title,
            rename: { try await onRename(renameState.draft) },
            onCommitted: { clearEditing() }
        )
    }

    private func clearEditing() {
        editingID = nil
        justCreatedID = nil
    }
}
