import SwiftUI

struct SpaceRow: View {
    let space: Space
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool
    @State private var isCreatingSpace: Bool = false

    @Environment(SpaceManager.self) private var spaceManager
    @Environment(SettingsManager.self) private var settingsManager

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
                    },
                    selectAllOnAppear: justCreatedID == space.id
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
                    Button("New Space") { createSpace() }
                        .disabled(isCreatingSpace)
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

    /// Stub-and-edit "New Space" trigger.
    private func createSpace() {
        guard !isCreatingSpace else { return }
        isCreatingSpace = true
        let label = settingsManager.settings.labels.sidebarSections.spaces
        let existing = spaceManager.spaces.map(\.title)
        // sidebarSections.spaces is plural ("Spaces") — use the singular
        // fallback via stripping a trailing "s" when present.
        let singular = label.hasSuffix("s") ? String(label.dropLast()) : label
        let title = DefaultTitleResolver.resolve(label: singular, existingTitles: existing)
        Task {
            defer { isCreatingSpace = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await spaceManager.create(name: title, color: nil, icon: nil)
                    },
                    onCreate: { newSpace in
                        editingID = newSpace.id
                        justCreatedID = newSpace.id
                    }
                )
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    private func commit() {
        guard draft != space.title else {
            editingID = nil
            justCreatedID = nil
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await spaceManager.rename(space, to: draft)
                editingID = nil  // success: dismiss edit mode
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
}
