import SwiftUI

struct NewTopicSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TopicManager.self) private var topicManager
    @Environment(SpaceManager.self) private var spaceManager

    @State private var name: String = ""
    @State private var selectedParents: Set<String> = []
    @State private var icon: String? = nil
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Topic")
                .font(.headline)

            Form {
                TextField("Name", text: $name)
                    .focused($nameFocused)
                LabeledContent("Icon") {
                    IconPickerField(symbol: $icon)
                }
                Section("Parent Spaces (optional)") {
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
                Button("Create") {
                    Task { await create() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 420, height: 480)
        .onAppear { nameFocused = true }
    }

    private func create() async {
        do {
            let parents = Array(selectedParents)
            let iconValue: String? = (icon?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) ? nil : icon
            try await topicManager.createTopic(name: name, parents: parents, icon: iconValue)
            dismiss()
        } catch let error as TopicValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendly(_ error: TopicValidator.ValidationError) -> String {
        switch error {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle: return "A Topic with that name already exists."
        case .parentNotFound: return "One of the selected parent Spaces no longer exists."
        }
    }
}
