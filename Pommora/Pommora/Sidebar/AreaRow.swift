import SwiftUI

struct AreaRow: View {
    let area: Area
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @State private var renameState = InlineRenameState()
    @FocusState private var renameFocused: Bool
    @State private var isCreatingArea: Bool = false

    @Environment(AreaManager.self) private var areaManager

    var body: some View {
        Group {
            if editingID == area.id {
                RenameableRow(
                    symbol: area.icon ?? "circle.fill",
                    symbolForeground: area.color?.swiftUIColor ?? .primary,
                    initialTitle: area.title,
                    draft: $renameState.draft,
                    renameFocused: $renameFocused,
                    onSubmit: { commit() },
                    onCancel: { clearEditing() },
                    onFocusLoss: {
                        if !renameState.isCommitting && editingID == area.id {
                            clearEditing()
                        }
                    },
                    selectAllOnAppear: justCreatedID == area.id
                )
            } else {
                SelectableRow(
                    title: area.title,
                    symbol: area.icon ?? "circle.fill",
                    tag: SelectionTag.area(area.id),
                    selection: $selection,
                    accent: area.color?.swiftUIColor
                )
                .contextMenu {
                    Button("New Area") { createArea() }
                        .disabled(isCreatingArea)
                    Divider()
                    Button("Edit Title") { startRename() }
                    Button("Change Color") { presentedSheet = .editColor(area) }
                    Button("Edit Icon") { presentedSheet = .editIcon(.area(area)) }
                    Divider()
                    Button("Delete", role: .destructive) {
                        confirmingDelete = .deleteArea(area)
                    }
                }
            }
        }
        .listRowBackground(
            SelectionChrome(isSelected: SelectionTag.area(area.id).matches(selection))
        )
    }

    private func startRename() {
        editingID = area.id
    }

    /// Stub-and-edit "New Area" trigger.
    private func createArea() {
        guard !isCreatingArea else { return }
        isCreatingArea = true
        let existing = areaManager.areas.map(\.title)
        let title = DefaultTitleResolver.resolve(label: "Area", existingTitles: existing)
        Task {
            defer { isCreatingArea = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await areaManager.create(name: title, color: nil, icon: nil)
                    },
                    onCreate: { newArea in
                        editingID = newArea.id
                        justCreatedID = newArea.id
                    }
                )
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    private func commit() {
        renameState.commit(
            currentTitle: area.title,
            rename: { try await areaManager.rename(area, to: renameState.draft) },
            onCommitted: { clearEditing() }
        )
    }

    private func clearEditing() {
        editingID = nil
        justCreatedID = nil
    }
}
