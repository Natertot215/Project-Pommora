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
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool

    var body: some View {
        if editingID == subtopic.id {
            renamingRow
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

    private var renamingRow: some View {
        HStack(spacing: 6) {
            Image(systemName: subtopic.icon ?? "doc.text")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .frame(width: 16, alignment: .leading)
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .focused($renameFocused)
                .onSubmit { commit() }
                .onKeyPress(.escape) { cancel(); return .handled }
                .onChange(of: renameFocused) { _, focused in
                    if !focused && !isCommitting && editingID == subtopic.id {
                        cancel()
                    }
                }
                .onAppear {
                    draft = subtopic.title
                    renameFocused = true
                }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commit() {
        guard draft != subtopic.title else { editingID = nil; return }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await topicManager.renameSubtopic(subtopic, to: draft)
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
