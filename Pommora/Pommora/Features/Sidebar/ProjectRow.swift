import SwiftUI

/// Renamed from `SubtopicRow` per ParadigmV2.
struct ProjectRow: View {
    let project: Project
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @Environment(ProjectManager.self) private var projectManager

    var body: some View {
        SidebarRow(
            id: project.id,
            title: project.title,
            symbol: project.icon ?? "doc.text",
            tag: .project(project.id),
            selection: $selection,
            editingID: $editingID,
            justCreatedID: $justCreatedID,
            onRename: { try await projectManager.rename(project, to: $0) }
        ) {
            Button("Edit Title") { editingID = project.id }
            Button("Edit Icon") { presentedSheet = .editIcon(.project(project)) }
            Divider()
            Button("Delete", role: .destructive) {
                confirmingDelete = .deleteProject(project)
            }
        }
        .listRowBackground(
            SelectionChrome(isSelected: SelectionTag.project(project.id).matches(selection))
        )
    }
}
