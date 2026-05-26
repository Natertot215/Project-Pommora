import SwiftUI

/// Sheet for creating a new Item. Mirrors `NewPageTypeSheet`'s Name + Icon
/// form pattern. Routes to `ItemContentManager.createItem(in:type:)` when
/// `collection` is non-nil (Set-scoped) or `createItem(inTypeRoot:)` when
/// `collection` is nil (Type-root).
struct NewItemSheet: View {
    let collection: ItemCollection?
    let type: ItemType

    @Environment(\.dismiss) private var dismiss
    @Environment(ItemContentManager.self) private var itemContentManager

    @State private var name: String = ""
    @State private var icon: String? = "doc"
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Item").font(.headline)
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
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let iconValue: String? = (icon?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) ? nil : icon
        do {
            if let collection {
                _ = try await itemContentManager.createItem(name: trimmed, icon: iconValue, in: collection, type: type)
            } else {
                _ = try await itemContentManager.createItem(name: trimmed, icon: iconValue, inTypeRoot: type)
            }
            dismiss()
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "\(error)"
        } catch {
            errorMessage = "\(error)"
        }
    }
}
