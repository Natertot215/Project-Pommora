import SwiftUI

/// Renamed from `NewSubtopicSheet` per ParadigmV2 (tier-3 label is now "Project").
struct NewProjectSheet: View {
    let parent: Topic
    @Environment(\.dismiss) private var dismiss
    @Environment(TopicManager.self) private var topicManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var name: String = ""
    @State private var icon: String? = nil
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New \(settingsManager.settings.labels.project.singular) in \"\(parent.title)\"")
                .font(.headline)
            Form {
                TextField("Title", text: $name).focused($nameFocused)
                LabeledContent("Icon") {
                    IconPickerField(symbol: $icon)
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
        .frame(width: 400, height: 260)
        .onAppear { nameFocused = true }
    }

    private func create() async {
        do {
            let iconValue: String? = (icon?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) ? nil : icon
            try await topicManager.createProject(name: name, inTopic: parent, icon: iconValue)
            dismiss()
        } catch let error as ProjectValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendly(_ error: ProjectValidator.ValidationError) -> String {
        let projectLabel = settingsManager.settings.labels.project.singular
        switch error {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle:
            return "A \(projectLabel) with that name already exists in this Topic."
        case .missingParent, .tooManyParents, .parentNotFound, .fileLocationMismatch:
            return "Internal validation error."
        }
    }
}
