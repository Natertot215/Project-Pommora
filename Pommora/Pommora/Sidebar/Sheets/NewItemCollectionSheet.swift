import SwiftUI

/// Sheet for creating a new Item Collection inside a given Item Type.
/// Mirrors `NewPageCollectionSheet`'s Name-only form pattern. Routes to
/// `ItemTypeManager.createItemCollection(name:inItemType:)`.
struct NewItemCollectionSheet: View {
    let type: ItemType
    @Environment(\.dismiss) private var dismiss
    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var name: String = ""
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New \(settingsManager.settings.labels.itemCollection.singular) in \"\(type.title)\"")
                .font(.headline)
            Form {
                TextField("Title", text: $name).focused($nameFocused)
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
            try await itemTypeManager.createItemCollection(name: name, inItemType: type)
            dismiss()
        } catch let error as ItemCollectionValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendly(_ error: ItemCollectionValidator.ValidationError) -> String {
        let set = settingsManager.settings.labels.itemCollection.singular
        let typeLabel = settingsManager.settings.labels.itemType.singular
        switch error {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle:
            return "A \(set) with that name already exists in this \(typeLabel)."
        }
    }
}
