import SwiftUI

/// Sheet for creating a new Item Type. Mirrors `NewPageTypeSheet`'s Name + Icon
/// form pattern. Routes to `ItemTypeManager.createItemType(name:icon:)`.
struct NewItemTypeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var name: String = ""
    @State private var icon: String? = "tray.full"
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New \(settingsManager.settings.labels.itemType.singular)").font(.headline)
            Form {
                TextField("Name", text: $name).focused($nameFocused)
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
            try await itemTypeManager.createItemType(name: name, icon: iconValue)
            dismiss()
        } catch let error as ItemTypeValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendly(_ error: ItemTypeValidator.ValidationError) -> String {
        switch error {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle:
            return "A \(settingsManager.settings.labels.itemType.singular) with that name already exists."
        }
    }
}
