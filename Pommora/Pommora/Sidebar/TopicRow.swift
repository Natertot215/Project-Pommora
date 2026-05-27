import SwiftUI

struct TopicRow: View {
    let topic: Topic
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @State private var expanded: Bool = false

    @Environment(TopicManager.self) private var topicManager
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool
    @State private var isCreatingTopic: Bool = false
    @State private var isCreatingProject: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(topicManager.projects(in: topic)) { project in
                ProjectRow(
                    project: project,
                    parentTopic: topic,
                    selection: $selection,
                    editingID: $editingID,
                    justCreatedID: $justCreatedID,
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
                selectAllOnAppear: justCreatedID == topic.id,
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
                Button("New Topic") { createTopic() }
                    .disabled(isCreatingTopic)
                Button("New \(projectLabel)") { createProject() }
                    .disabled(isCreatingProject)
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

    /// Stub-and-edit "New Topic" trigger. New Topics inherit this Topic's
    /// current parents (Spaces) — matches the parent-selection UX of the
    /// retired NewTopicSheet, where the freshly-created Topic was initially
    /// rootless and the user picked parents via the sheet. With stub-and-edit
    /// the parents are inherited from the row that fired the action, and the
    /// user can adjust later via "Edit Parents".
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
                            name: title, parents: topic.parents, icon: nil
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

    /// Stub-and-edit "New Project (in This Topic)" trigger.
    private func createProject() {
        guard !isCreatingProject else { return }
        isCreatingProject = true
        let label = settingsManager.settings.labels.project.singular
        let existing = topicManager.projects(in: topic).map(\.title)
        let title = DefaultTitleResolver.resolve(label: label, existingTitles: existing)
        Task {
            defer { isCreatingProject = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await topicManager.createProject(
                            name: title, inTopic: topic, icon: nil
                        )
                    },
                    onCreate: { newProject in
                        editingID = newProject.id
                        justCreatedID = newProject.id
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
