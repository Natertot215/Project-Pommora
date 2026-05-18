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

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(topicManager.subtopics(in: topic)) { sub in
                SubtopicRow(
                    subtopic: sub,
                    parentTopic: topic,
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
            }
        } label: {
            label
        }
        .listRowBackground(
            SelectionChrome(
                isSelected: SelectionTag.topic(topic.id).matches(selection),
                style: .disclosure
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
                Button("New Topic") { presentedSheet = .newTopic }
                Button("New Sub-topic (in This Topic)") { presentedSheet = .newSubtopic(parent: topic) }
                Divider()
                Button("Rename") { editingID = topic.id }
                Button("Edit Parents") { presentedSheet = .editTopicParents(topic) }
                Button("Change Icon") { presentedSheet = .editIcon(.topic(topic)) }
                Divider()
                Button("Delete", role: .destructive) {
                    confirmingDelete = .deleteTopic(topic, subtopicCount: topicManager.subtopics(in: topic).count)
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
                .onKeyPress(.escape) { cancel(); return .handled }
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
        guard draft != topic.title else { editingID = nil; return }
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
                    .fill(space.color.swiftUIColor)
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
