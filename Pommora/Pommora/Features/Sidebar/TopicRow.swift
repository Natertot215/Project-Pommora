import SwiftUI

struct TopicRow: View {
    let topic: Topic
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @State private var isCreatingTopic: Bool = false
    @Environment(TopicManager.self) private var topicManager

    var body: some View {
        SidebarRow(
            id: topic.id,
            title: topic.title,
            symbol: topic.icon ?? "folder",
            tag: .topic(topic.id),
            selection: $selection,
            editingID: $editingID,
            justCreatedID: $justCreatedID,
            onRename: { try await topicManager.rename(topic, to: $0) }
        ) {
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
        .listRowBackground(
            SelectionChrome(isSelected: SelectionTag.topic(topic.id).matches(selection))
        )
    }

    /// Stub-and-edit "New Topic" trigger — creates a free-standing tier-2 Topic.
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
                        try await topicManager.create(name: title, icon: nil)
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
}
