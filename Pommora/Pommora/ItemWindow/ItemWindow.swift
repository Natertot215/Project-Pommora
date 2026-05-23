import SwiftUI

struct ItemWindow: View {
    let item: Item
    @Environment(\.dismiss) private var dismiss
    @Environment(ContentManager.self) private var contentManager
    @Environment(PageTypeManager.self) private var vaultManager

    @State private var draftTitle: String = ""
    @State private var draftIcon: String = ""
    @State private var draftDescription: String = ""
    @State private var draftProperties: [String: PropertyValue] = [:]
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    titleSection
                    iconSection
                    descriptionSection
                    Divider()
                    propertiesSection
                    Divider()
                    relationsSection
                    Divider()
                    metaSection
                }
                .padding()
            }
            Divider()
            footer
        }
        .frame(width: 480, height: 580)
        .onAppear {
            hydrate()
            guard let recents = AppGlobals.recentsManager else { return }
            let ref = EntityStateRef(kind: .item, id: item.id, title: item.title)
            recents.record(ref)
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: draftIcon.isEmpty ? "list.bullet.rectangle" : draftIcon)
                .font(.system(size: 20))
            Text(draftTitle).font(.headline)
            Spacer()
            Button("Done") { dismiss() }
        }
        .padding()
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Title").font(.caption).foregroundStyle(.secondary)
            TextField("", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Icon").font(.caption).foregroundStyle(.secondary)
            TextField("SF Symbol name", text: $draftIcon)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Description").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(draftDescription.count) / 250")
                    .font(.caption)
                    .foregroundStyle(
                        draftDescription.count > 250
                            ? AnyShapeStyle(Color.red) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
            }
            TextEditor(text: $draftDescription)
                .frame(minHeight: 60, maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.gray.opacity(0.3))
                )
        }
    }

    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Properties").font(.caption).foregroundStyle(.secondary)
            if let vault = vaultForItem() {
                if vault.properties.isEmpty {
                    Text("No properties in this Vault's schema.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(vault.properties) { def in
                        PropertyEditorRow(
                            definition: def,
                            value: Binding(
                                get: { draftProperties[def.name] ?? .null },
                                set: { draftProperties[def.name] = $0 }
                            )
                        )
                    }
                }
            } else {
                Text("Parent Vault not found.").font(.callout).foregroundStyle(.red)
            }
        }
    }

    private var relationsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Relations").font(.caption).foregroundStyle(.secondary)
            relationLine(label: "Tier 1 (Spaces)", ids: item.tier1)
            relationLine(label: "Tier 2 (Topics)", ids: item.tier2)
            relationLine(label: "Tier 3 (Sub-topics)", ids: item.tier3)
            Text("Property panel coming v0.3.0")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func relationLine(label: String, ids: [String]) -> some View {
        HStack {
            Text(label).frame(width: 140, alignment: .leading).foregroundStyle(.secondary)
            Text(ids.isEmpty ? "—" : ids.joined(separator: ", "))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.callout)
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Meta").font(.caption).foregroundStyle(.secondary)
            Text("ID: \(item.id)").font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
            Text("Created: \(item.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                .foregroundStyle(.tertiary)
            Text("Modified: \(item.modifiedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var footer: some View {
        HStack {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Save") {
                Task { await save() }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - State helpers

    private func hydrate() {
        draftTitle = item.title
        draftIcon = item.icon ?? ""
        draftDescription = item.description
        draftProperties = item.properties
    }

    private func vaultForItem() -> PageType? {
        // Items live in Collections; find the Vault whose Collection holds this Item
        for vault in vaultManager.types {
            for coll in vaultManager.pageCollections(in: vault) {
                if contentManager.items(in: coll).contains(where: { $0.id == item.id }) {
                    return vault
                }
            }
        }
        return nil
    }

    private func save() async {
        guard let vault = vaultForItem() else {
            errorMessage = "Parent Vault not found."
            return
        }
        guard
            let coll =
                (vaultManager.pageCollections(in: vault).first {
                    contentManager.items(in: $0).contains(where: { $0.id == item.id })
                })
        else {
            errorMessage = "Parent Collection not found."
            return
        }

        var updated = item
        applyDraft(to: &updated)

        do {
            // If title changed, rename first
            if updated.title != item.title {
                try await contentManager.renameItem(item, to: updated.title, in: coll, vault: vault)
                // Force reload from disk before refetch — guards against stale in-memory state
                await contentManager.loadAll(for: coll)
                guard let refetched = contentManager.items(in: coll).first(where: { $0.id == item.id }) else {
                    errorMessage =
                        "Rename succeeded on disk but in-memory refetch failed. Item state may be stale; please close + reopen."
                    dismiss()
                    return
                }
                updated = refetched
                applyDraft(to: &updated)
            }
            try await contentManager.updateItem(updated, in: coll, vault: vault)
            dismiss()
        } catch let error as ItemValidator.ValidationError {
            errorMessage = friendly(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Apply the draft state into the given Item — used at both the pre-rename
    /// site and the post-rename refetch site so the property-assignment block
    /// doesn't drift between the two.
    private func applyDraft(to item: inout Item) {
        item.title = draftTitle
        item.icon = draftIcon.trimmingCharacters(in: .whitespaces).isEmpty ? nil : draftIcon
        item.description = draftDescription
        item.properties = draftProperties
    }

    private func friendly(_ error: ItemValidator.ValidationError) -> String {
        switch error {
        case .emptyTitle: return "Title can't be empty."
        case .invalidTitleCharacters: return "Title can't contain / \\ :"
        case .duplicateTitle: return "Another Item already has that name in this Collection."
        case .descriptionTooLong: return "Description over 250 characters."
        case .tierMismatch: return "Internal: tier reference invalid."
        case .unknownProperty(let n): return "Unknown property '\(n)' for this Vault."
        case .propertyTypeMismatch(let n): return "Property '\(n)' has wrong type."
        }
    }
}
