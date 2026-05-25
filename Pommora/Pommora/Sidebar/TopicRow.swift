import SwiftUI

struct TopicRow: View {
    let topic: Topic
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @State private var expanded: Bool = false

    @Environment(TopicManager.self) private var topicManager
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(topicManager.projects(in: topic)) { project in
                ProjectRow(
                    project: project,
                    parentTopic: topic,
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
                .tag(SelectionTag.project(project.id))
            }
            .onMove { source, destination in
                withAnimation(.snappy) {
                    topicManager.reorderProjects(
                        in: topic, fromOffsets: source, toOffset: destination
                    )
                }
            }
        } label: {
            label
        }
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
                trailing: {
                    ParentSpaceTags(topic: topic, spaceManager: spaceManager)
                }
            )
        } else {
            SelectableRow(
                title: topic.title,
                symbol: topic.icon ?? "folder",
                tag: SelectionTag.topic(topic.id),
                selection: $selection,
                accent: nil,
                trailing: {
                    ParentSpaceTags(topic: topic, spaceManager: spaceManager)
                }
            )
            .contextMenu {
                let projectLabel = settingsManager.settings.labels.project.singular
                Button("New Topic") { presentedSheet = .newTopic }
                Button("New \(projectLabel) (in This Topic)") { presentedSheet = .newProject(parent: topic) }
                Divider()
                Button("Rename") { editingID = topic.id }
                Button("Edit Parents") { presentedSheet = .editTopicParents(topic) }
                Button("Change Icon") { presentedSheet = .editIcon(.topic(topic)) }
                Divider()
                Button("Delete", role: .destructive) {
                    confirmingDelete = .deleteTopic(topic, projectCount: topicManager.projects(in: topic).count)
                }
            }
        }
    }

    private func commit() {
        guard draft != topic.title else {
            editingID = nil
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await topicManager.renameTopic(topic, to: draft)
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

/// Renders one small color dot per parent Space of the Topic.
struct ParentSpaceTags: View {
    let topic: Topic
    let spaceManager: SpaceManager

    var body: some View {
        HStack(spacing: 2) {
            ForEach(parentSpaces, id: \.id) { space in
                Circle()
                    .fill(space.color?.swiftUIColor ?? .secondary)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var parentSpaces: [Space] {
        topic.parents.compactMap { id in
            spaceManager.spaces.first { $0.id == id }
        }
    }
}
