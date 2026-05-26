import SwiftUI

struct NewPageSheet: View {
    let parent: PageParent
    @Environment(\.dismiss) private var dismiss
    @Environment(PageContentManager.self) private var contentManager

    @State private var name: String = ""
    @State private var icon: String? = "doc.text"
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(headerText).font(.headline)
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

    private var headerText: String {
        switch parent {
        case .collection(let coll, _):
            return "New Page in \"\(coll.title)\""
        case .vaultRoot(let vault):
            return "New Page in \"\(vault.title)\""
        }
    }

    private func create() async {
        let iconValue: String? = (icon?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) ? nil : icon
        do {
            switch parent {
            case .collection(let coll, let vault):
                try await contentManager.createPage(name: name, icon: iconValue, in: coll, vault: vault)
            case .vaultRoot(let vault):
                _ = try await contentManager.createPage(name: name, icon: iconValue, inVaultRoot: vault)
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
        case .missingCreatedAt: return "Internal: created_at not set."
        case .tierMismatch: return "Internal: tier reference invalid."
        case .unknownProperty(let id): return "Property '\(id)' not in Vault schema."
        case .propertyTypeMismatch(let id): return "Property '\(id)' has wrong type."
        }
    }
}
