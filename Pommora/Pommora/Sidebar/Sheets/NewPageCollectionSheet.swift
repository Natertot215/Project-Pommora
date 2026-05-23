import SwiftUI

struct NewPageCollectionSheet: View {
    let vault: PageType
    @Environment(\.dismiss) private var dismiss
    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var name: String = ""
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New \(settingsManager.settings.labels.pageCollection.singular) in \"\(vault.title)\"")
                .font(.headline)
            Form {
                TextField("Name", text: $name).focused($nameFocused)
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
        .frame(width: 380, height: 220)
        .onAppear { nameFocused = true }
    }

    private func create() async {
        do {
            try await vaultManager.createPageCollection(name: name, inPageType: vault)
            dismiss()
        } catch let error as PageCollectionValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendly(_ error: PageCollectionValidator.ValidationError) -> String {
        let collection = settingsManager.settings.labels.pageCollection.singular
        let vaultLabel = settingsManager.settings.labels.pageType.singular
        switch error {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle:
            return "A \(collection) with that name already exists in this \(vaultLabel)."
        }
    }
}
