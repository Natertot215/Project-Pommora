import SwiftUI

struct TopicRow: View {
    let topic: Topic
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @Environment(TopicManager.self) private var topicManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool
    @State private var isCreatingTopic: Bool = false

    var body: some View {
        label
            .listRowBackground(
                SelectionChrome(
                    isSelected: SelectionTag.topic(topic.id).matches(selection)
                )
            )
    }

    @ViewBuilder
    private var label: some View {
        if editingID == topic.id {
            RenameableRow(
                symbol: topic.icon ?? "folder",
                initialTitle: topic.title,
                draft: $draft,
                renameFocused: $renameFocused,
                onSubmit: { commit() },
                onCancel: { cancel() },
                onFocusLoss: {
                    if !isCommitting && editingID == topic.id {
                        cancel()
                    }
                },
                selectAllOnAppear: justCreatedID == topic.id
            )
        } else {
            SelectableRow(
                title: topic.title,
                symbol: topic.icon ?? "folder",
                tag: SelectionTag.topic(topic.id),
                selection: $selection,
                accent: nil
            )
            .contextMenu {
                Button("New Topic") { createTopic() }
                    .disabled(isCreatingTopic)
                Divider()
                Button("Edit Title") { editingID = topic.id }
                Button("Edit Icon") { presentedSheet = .editIcon(.topic(topic)) }
                Divider()
                Button("Delete", role: .destructive) {
                    confirmingDelete = .deleteTopic(topic)
                }
            }
        }
    }

    /// Stub-and-edit "New Topic" trigger — creates a free-standing tier-2
    /// Topic (Topics no longer have parents).
    private func createTopic() {
        guard !isCreatingTopic else { return }
        isCreatingTopic = true
        let existing = topicManager.topics.map(\.title)
        let title = DefaultTitleResolver.resolve(label: "Topic", existingTitles: existing)
        Task {
            defer { isCreatingTopic = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await topicManager.createTopic(
                            name: title, icon: nil
                        )
                    },
                    onCreate: { newTopic in
                        editingID = newTopic.id
                        justCreatedID = newTopic.id
                    }
                )
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    private func commit() {
        guard draft != topic.title else {
            editingID = nil
            justCreatedID = nil
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await topicManager.renameTopic(topic, to: draft)
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
