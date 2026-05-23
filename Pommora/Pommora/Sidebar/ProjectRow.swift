import SwiftUI

/// Renamed from `SubtopicRow` per ParadigmV2.
struct ProjectRow: View {
    let project: Project
    let parentTopic: Topic
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @Environment(TopicManager.self) private var topicManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool

    var body: some View {
        Group {
            if editingID == project.id {
                renamingRow
            } else {
                SelectableRow(
                    title: project.title,
                    symbol: project.icon ?? "doc.text",
                    tag: SelectionTag.project(project.id),
                    selection: $selection,
                    accent: nil,
                    onSelect: { selection = .project(project) }
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
        .reorderable(
            kind: .project,
            id: project.id,
            containerID: parentTopic.id,
            nexusID: topicManager.nexusID,
            symbol: project.icon ?? "doc.text",
            title: project.title,
            accent: nil,
            onDrop: { payload, position in
                let arr = topicManager.projects(in: parentTopic)
                guard
                    let from = arr.firstIndex(where: { $0.id == payload.id }),
                    let targetIdx = arr.firstIndex(where: { $0.id == project.id })
                else { return }
                let toOffset = position == .above ? targetIdx : targetIdx + 1
                topicManager.reorderProjects(
                    in: parentTopic,
                    fromOffsets: IndexSet(integer: from),
                    toOffset: toOffset
                )
            }
        )
    }

    private var renamingRow: some View {
        HStack(spacing: 8) {
            Image(systemName: project.icon ?? "doc.text")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 16, height: 16, alignment: .center)
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .focused($renameFocused)
                .onSubmit { commit() }
                .onKeyPress(.escape) {
                    cancel()
                    return .handled
                }
                .onChange(of: renameFocused) { _, focused in
                    if !focused && !isCommitting && editingID == project.id {
                        cancel()
                    }
                }
                .onAppear {
                    draft = project.title
                    renameFocused = true
                }
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
        .padding(.trailing, 0)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commit() {
        guard draft != project.title else {
            editingID = nil
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await topicManager.renameProject(project, to: draft)
                editingID = nil
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
