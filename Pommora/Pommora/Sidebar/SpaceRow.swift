import SwiftUI

struct SpaceRow: View {
    let space: Space
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @State private var draft: String = ""
    @FocusState private var renameFocused: Bool

    @Environment(SpaceManager.self) private var spaceManager

    var body: some View {
        Group {
            if editingID == space.id {
                renameField
            } else {
                SelectableRow(
                    title: space.title,
                    symbol: space.icon ?? "circle.fill",
                    tag: SelectionTag.space(space.id),
                    selection: $selection,
                    accent: space.color.swiftUIColor,
                    onSelect: { selection = .space(space) }
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
    }

    private var renameField: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .focused($renameFocused)
            .onSubmit { commit() }
            .onKeyPress(.escape) { cancel(); return .handled }
            .onAppear {
                draft = space.title
                renameFocused = true
            }
    }

    private func startRename() {
        editingID = space.id
    }

    private func commit() {
        guard draft != space.title else { editingID = nil; return }
        Task {
            do {
                try await spaceManager.rename(space, to: draft)
                editingID = nil  // success: dismiss edit mode
            } catch {
                // editingID stays set on failure so user can retry; pendingError will be set in Commit 4
            }
        }
    }

    private func cancel() {
        editingID = nil
    }
}
