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
            }
        } label: {
            // .reorderable wraps the label only so the chevron tap area stays
            // free for expand/collapse (see PageTypeRow for full rationale).
            label.reorderable(
                kind: .topic,
                id: topic.id,
                containerID: nil,
                nexusID: topicManager.nexusID,
                symbol: topic.icon ?? "folder",
                title: topic.title,
                accent: nil,
                onDrop: { payload, position in
                    let arr = topicManager.topics
                    guard
                        let from = arr.firstIndex(where: { $0.id == payload.id }),
                        let targetIdx = arr.firstIndex(where: { $0.id == topic.id })
                    else { return }
                    let toOffset = position == .above ? targetIdx : targetIdx + 1
                    topicManager.reorderTopics(
                        fromOffsets: IndexSet(integer: from),
                        toOffset: toOffset
                    )
                }
            )
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
            renamingRow
        } else {
            SelectableRow(
                title: topic.title,
                symbol: topic.icon ?? "folder",
                tag: SelectionTag.topic(topic.id),
                selection: $selection,
                accent: nil,
                onSelect: { selection = .topic(topic) },
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

    /// Mirrors SelectableRow's HStack shape — icon stays visible, trailing
    /// ParentSpaceTags dots stay visible for visual stability across rename
    /// mode. Only the text slot becomes a TextField.
    private var renamingRow: some View {
        HStack(spacing: 8) {
            Image(systemName: topic.icon ?? "folder")
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
                    if !focused && !isCommitting && editingID == topic.id {
                        cancel()
                    }
                }
                .onAppear {
                    draft = topic.title
                    renameFocused = true
                }
            Spacer(minLength: 0)
            ParentSpaceTags(topic: topic, spaceManager: spaceManager)
        }
        .padding(.leading, 2)
        .padding(.trailing, 0)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
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
