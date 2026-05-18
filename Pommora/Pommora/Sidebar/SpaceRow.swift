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
                renamingRow
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
        .listRowBackground(
            SelectionChrome(isSelected: SelectionTag.space(space.id).matches(selection))
        )
    }

    /// Mirrors SelectableRow's HStack shape (icon + text slot + trailing spacer)
    /// so the row doesn't visually jump when entering/exiting rename mode.
    private var renamingRow: some View {
        HStack(spacing: 6) {
            Image(systemName: space.icon ?? "circle.fill")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(space.color.swiftUIColor)
                .frame(width: 16, alignment: .leading)
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .focused($renameFocused)
                .onSubmit { commit() }
                .onKeyPress(.escape) { cancel(); return .handled }
                .onChange(of: renameFocused) { _, focused in
                    if !focused && !isCommitting && editingID == space.id {
                        cancel()
                    }
                }
                .onAppear {
                    draft = space.title
                    renameFocused = true
                }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func startRename() {
        editingID = space.id
    }

    private func commit() {
        guard draft != space.title else { editingID = nil; return }
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
