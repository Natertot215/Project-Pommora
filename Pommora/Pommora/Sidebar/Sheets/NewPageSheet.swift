import SwiftUI

struct NewPageSheet: View {
    let parent: PageParent
    @Environment(\.dismiss) private var dismiss
    @Environment(PageContentManager.self) private var contentManager

    @State private var name: String = ""
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(headerText).font(.headline)
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

    private var headerText: String {
        switch parent {
        case .collection(let coll, _):
            return "New Page in \"\(coll.title)\""
        case .vaultRoot(let vault):
            return "New Page in \"\(vault.title)\""
        }
    }

    private func create() async {
        do {
            switch parent {
            case .collection(let coll, let vault):
                try await contentManager.createPage(name: name, in: coll, vault: vault)
            case .vaultRoot(let vault):
                _ = try await contentManager.createPage(name: name, inVaultRoot: vault)
            }
            dismiss()
        } catch let error as PageValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func friendly(_ error: PageValidator.ValidationError) -> String {
        switch error {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle:
            switch parent {
            case .collection: return "A Page with that name already exists in this Collection."
            case .vaultRoot: return "A Page with that name already exists in this Vault's root."
            }
        case .missingCreatedAt: return "Internal: created_at not set."
        case .tierMismatch: return "Internal: tier reference invalid."
        case .unknownProperty(let n): return "Property '\(n)' not in Vault schema."
        case .propertyTypeMismatch(let n): return "Property '\(n)' has wrong type."
        }
    }
}
