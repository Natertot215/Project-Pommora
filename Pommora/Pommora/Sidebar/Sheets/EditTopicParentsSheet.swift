import SwiftUI

struct EditTopicParentsSheet: View {
    let topic: Topic
    @Environment(\.dismiss) private var dismiss
    @Environment(TopicManager.self) private var topicManager
    @Environment(SpaceManager.self) private var spaceManager

    @State private var selectedParents: Set<String>
    @State private var errorMessage: String?

    init(topic: Topic) {
        self.topic = topic
        _selectedParents = State(initialValue: Set(topic.parents))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Parents for \"\(topic.title)\"").font(.headline)
            Form {
                Section("Parent Spaces") {
                    ForEach(spaceManager.spaces) { space in
                        Toggle(
                            isOn: Binding(
                                get: { selectedParents.contains(space.id) },
                                set: { v in
                                    if v { selectedParents.insert(space.id) } else { selectedParents.remove(space.id) }
                                }
                            )
                        ) {
                            HStack {
                                Circle().fill(space.color?.swiftUIColor ?? .secondary).frame(width: 8, height: 8)
                                Text(space.title)
                            }
                        }
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420, height: 440)
    }

    private func save() async {
        do {
            try await topicManager.updateTopicParents(topic, to: Array(selectedParents))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
