import SwiftUI

struct SpaceRow: View {
    let space: Space
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool

    @Environment(SpaceManager.self) private var spaceManager

    var body: some View {
        Group {
            if editingID == space.id {
                RenameableRow(
                    symbol: space.icon ?? "circle.fill",
                    symbolForeground: space.color?.swiftUIColor ?? .primary,
                    initialTitle: space.title,
                    draft: $draft,
                    renameFocused: $renameFocused,
                    onSubmit: { commit() },
                    onCancel: { cancel() },
                    onFocusLoss: {
                        if !isCommitting && editingID == space.id {
                            cancel()
                        }
                    }
                )
            } else {
                SelectableRow(
                    title: space.title,
                    symbol: space.icon ?? "circle.fill",
                    tag: SelectionTag.space(space.id),
                    selection: $selection,
                    accent: space.color?.swiftUIColor
                )
                .contextMenu {
                    Button("New Space") { presentedSheet = .newSpace }
                    Divider()
                    Button("Rename") { startRename() }
                    Button("Change Color") { presentedSheet = .editColor(space) }
                    Button("Change Icon") { presentedSheet = .editIcon(.space(space)) }
                    Divider()
                    Button("Delete", role: .destructive) {
                        confirmingDelete = .deleteSpace(space)
                    }
                }
            }
        }
        .listRowBackground(
            SelectionChrome(isSelected: SelectionTag.space(space.id).matches(selection))
        )
    }

    private func startRename() {
        editingID = space.id
    }

    private func commit() {
        guard draft != space.title else {
            editingID = nil
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await spaceManager.rename(space, to: draft)
                editingID = nil  // success: dismiss edit mode
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
