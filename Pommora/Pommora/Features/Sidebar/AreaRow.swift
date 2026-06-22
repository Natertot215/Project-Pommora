import SwiftUI

struct AreaRow: View {
    let area: Area
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @State private var isCreatingArea: Bool = false
    @Environment(AreaManager.self) private var areaManager

    var body: some View {
        SidebarRow(
            id: area.id,
            title: area.title,
            symbol: area.icon ?? "circle.fill",
            tag: .area(area.id),
            selection: $selection,
            editingID: $editingID,
            justCreatedID: $justCreatedID,
            onRename: { try await areaManager.rename(area, to: $0) }
        ) {
            Button("New Area") { createArea() }
                .disabled(isCreatingArea)
            Divider()
            Button("Edit Title") { editingID = area.id }
            Button("Edit Icon") { presentedSheet = .editIcon(.area(area)) }
            Divider()
            Button("Delete", role: .destructive) {
                confirmingDelete = .deleteArea(area)
            }
        }
        .listRowBackground(
            SelectionChrome(isSelected: SelectionTag.area(area.id).matches(selection))
        )
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
                        try await areaManager.create(name: title, icon: nil)
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
}
