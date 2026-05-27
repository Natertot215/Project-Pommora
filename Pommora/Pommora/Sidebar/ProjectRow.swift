import SwiftUI

/// Renamed from `SubtopicRow` per ParadigmV2.
struct ProjectRow: View {
    let project: Project
    let parentTopic: Topic
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @Environment(TopicManager.self) private var topicManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool

    var body: some View {
        Group {
            if editingID == project.id {
                RenameableRow(
                    symbol: project.icon ?? "doc.text",
                    initialTitle: project.title,
                    draft: $draft,
                    renameFocused: $renameFocused,
                    onSubmit: { commit() },
                    onCancel: { cancel() },
                    onFocusLoss: {
                        if !isCommitting && editingID == project.id {
                            cancel()
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
                    Button("Rename") { editingID = project.id }
                    Button("Change Icon") { presentedSheet = .editIcon(.project(project)) }
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
        guard draft != project.title else {
            editingID = nil
            justCreatedID = nil
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await topicManager.renameProject(project, to: draft)
                editingID = nil
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
