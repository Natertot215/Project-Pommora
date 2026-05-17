import SwiftUI

struct SubtopicRow: View {
    let subtopic: Subtopic
    let parentTopic: Topic
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @Environment(TopicManager.self) private var topicManager

    @State private var draft: String = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        Group {
            if editingID == subtopic.id {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($renameFocused)
                    .onSubmit { commit() }
                    .onKeyPress(.escape) { editingID = nil; return .handled }
                    .onAppear {
                        draft = subtopic.title
                        renameFocused = true
                    }
            } else {
                SelectableRow(
                    title: subtopic.title,
                    symbol: subtopic.icon ?? "doc.text",
                    tag: SelectionTag.subtopic(subtopic.id),
                    selection: $selection,
                    accent: nil,
                    onSelect: { selection = .subtopic(subtopic) }
                )
                .contextMenu {
                    Button("Rename") { editingID = subtopic.id }
                    Button("Change Icon") { presentedSheet = .editIcon(.subtopic(subtopic)) }
                    Divider()
                    Button("Delete", role: .destructive) {
                        confirmingDelete = .deleteSubtopic(subtopic)
                    }
                }
            }
        }
    }

    private func commit() {
        guard draft != subtopic.title else { editingID = nil; return }
        Task {
            do { try await topicManager.renameSubtopic(subtopic, to: draft) } catch {}
            editingID = nil
        }
    }
}
