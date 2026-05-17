import SwiftUI

struct NewSpaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SpaceManager.self) private var spaceManager

    @State private var name: String = ""
    @State private var color: SpaceColor = .blue
    @State private var icon: String = "person.circle"
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Space")
                .font(.headline)

            Form {
                TextField("Name", text: $name)
                    .focused($nameFocused)
                LabeledContent("Color") {
                    SpaceColorPicker(color: $color)
                }
                TextField("Icon (SF Symbol name)", text: $icon)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
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
        .frame(width: 400, height: 320)
        .onAppear { nameFocused = true }
    }

    private func create() async {
        do {
            let iconValue: String? = icon.trimmingCharacters(in: .whitespaces).isEmpty ? nil : icon
            try await spaceManager.create(name: name, color: color, icon: iconValue)
            dismiss()
        } catch let error as SpaceValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendly(_ error: SpaceValidator.ValidationError) -> String {
        switch error {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle: return "A Space with that name already exists."
        }
    }
}
