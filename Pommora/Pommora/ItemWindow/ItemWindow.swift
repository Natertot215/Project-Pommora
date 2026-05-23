import SwiftUI

struct ItemWindow: View {
    let item: Item
    @Environment(\.dismiss) private var dismiss

    // ParadigmV2 (Task 5.5): Item lookup + persistence has moved off the
    // PageType graph onto ItemContentManager + ItemType. The Phase 6 rewire
    // ships the Items-side resolver + persistence; for now the window is
    // preserved as a read-only preview that can't save / rename.
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
        // TODO Phase 6: walk ItemTypeManager + ItemContentManager instead.
        // Returning nil during Phase 5 disables the property-editor branch
        // (the view falls into the "Parent Vault not found" placeholder).
        _ = vaultManager
        return nil
    }

    private func save() async {
        // TODO Phase 6: route through ItemContentManager.renameItem / updateItem
        // once the Items-side resolver lands. Until then surface a friendly notice.
        errorMessage = "Item edits are temporarily disabled while the Items-side surface rebuilds (ParadigmV2 Phase 6)."
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
