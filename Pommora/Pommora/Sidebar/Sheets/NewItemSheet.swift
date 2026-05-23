import SwiftUI

struct NewItemSheet: View {
    let collection: Pommora.Collection
    let vault: PageType
    @Environment(\.dismiss) private var dismiss
    @Environment(ContentManager.self) private var contentManager

    @State private var name: String = ""
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Item in \"\(collection.title)\"").font(.headline)
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
            try await contentManager.createItem(name: name, in: collection, vault: vault)
            dismiss()
        } catch let error as ItemValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendly(_ error: ItemValidator.ValidationError) -> String {
        switch error {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle: return "An Item with that name already exists."
        case .descriptionTooLong: return "Description over 250 characters."
        case .tierMismatch: return "Internal: tier reference invalid."
        case .unknownProperty(let n): return "Property '\(n)' not in Vault schema."
        case .propertyTypeMismatch(let n): return "Property '\(n)' has wrong type."
        }
    }
}
