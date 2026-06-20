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

    @State private var renameState = InlineRenameState()
    @FocusState private var renameFocused: Bool

    var body: some View {
        Group {
            if editingID == project.id {
                RenameableRow(
                    symbol: project.icon ?? "doc.text",
                    initialTitle: project.title,
                    draft: $renameState.draft,
                    renameFocused: $renameFocused,
                    onSubmit: { commit() },
                    onCancel: { clearEditing() },
                    onFocusLoss: {
                        if !renameState.isCommitting && editingID == project.id {
                            clearEditing()
                        }
                    },
                    selectAllOnAppear: justCreatedID == project.id
                )
            } else {
                SelectableRow(
                    title: project.title,
                    symbol: project.icon ?? "doc.text",
                    tag: SelectionTag.project(project.id),
                    selection: $selection,
                    accent: nil
                )
                .contextMenu {
                    Button("Edit Title") { editingID = project.id }
                    Button("Edit Icon") { presentedSheet = .editIcon(.project(project)) }
                    Divider()
                    Button("Delete", role: .destructive) {
                        confirmingDelete = .deleteProject(project)
                    }
                }
            }
        }
        .listRowBackground(
            SelectionChrome(isSelected: SelectionTag.project(project.id).matches(selection))
        )
    }

    private func commit() {
        renameState.commit(
            currentTitle: project.title,
            rename: { try await projectManager.rename(project, to: renameState.draft) },
            onCommitted: { clearEditing() }
        )
    }

    private func clearEditing() {
        editingID = nil
        justCreatedID = nil
    }
}
