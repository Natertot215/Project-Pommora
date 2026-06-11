import SwiftUI

struct AreaRow: View {
    let area: Area
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool
    @State private var isCreatingArea: Bool = false

    @Environment(AreaManager.self) private var areaManager
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        Group {
            if editingID == area.id {
                RenameableRow(
                    symbol: area.icon ?? "circle.fill",
                    symbolForeground: area.color?.swiftUIColor ?? .primary,
                    initialTitle: area.title,
                    draft: $draft,
                    renameFocused: $renameFocused,
                    onSubmit: { commit() },
                    onCancel: { cancel() },
                    onFocusLoss: {
                        if !isCommitting && editingID == area.id {
                            cancel()
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
        let label = settingsManager.settings.labels.sidebarSections.areas
        let existing = areaManager.areas.map(\.title)
        // sidebarSections.areas is plural ("Areas") — use the singular
        // fallback via stripping a trailing "s" when present.
        let singular = label.hasSuffix("s") ? String(label.dropLast()) : label
        let title = DefaultTitleResolver.resolve(label: singular, existingTitles: existing)
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
        guard draft != area.title else {
            editingID = nil
            justCreatedID = nil
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await areaManager.rename(area, to: draft)
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
