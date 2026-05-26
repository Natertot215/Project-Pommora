import SwiftUI

struct NewPageTypeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var name: String = ""
    @State private var icon: String? = "tray.2"
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New \(settingsManager.settings.labels.pageType.singular)").font(.headline)
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
            try await pageTypeManager.createPageType(name: name, icon: iconValue)
            dismiss()
        } catch let error as PageTypeValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendly(_ error: PageTypeValidator.ValidationError) -> String {
        switch error {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle:
            return "A \(settingsManager.settings.labels.pageType.singular) with that name already exists."
        }
    }
}
