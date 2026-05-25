import SwiftUI

struct ItemWindow: View {
    let item: Item
    @Environment(\.dismiss) private var dismiss

    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(ItemContentManager.self) private var itemContentManager

    @State private var draftTitle: String = ""
    @State private var draftIcon: String = ""
    @State private var draftDescription: String = ""
    @State private var draftProperties: [String: PropertyValue] = [:]
    @State private var errorMessage: String?

    /// The ItemType schema captured at open time — the baseline for drift detection.
    /// Resolved once on `.onAppear` by scanning ItemTypeManager state.
    @State private var originalItemType: ItemType?

    /// Set when drift is detected on save; drives the SchemaConflictDialog sheet.
    @State private var schemaConflict: SchemaConflictPayload?

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
        .sheet(item: $schemaConflict) { payload in
            SchemaConflictDialog(
                isPresented: Binding(
                    get: { schemaConflict != nil },
                    set: { if !$0 { schemaConflict = nil } }
                ),
                removedPropertyNames: payload.removed,
                typeChangedPropertyNames: payload.typeChanged,
                onReload: {
                    reloadFromDisk()
                    schemaConflict = nil
                },
                onSaveValidSubset: {
                    Task { await saveValidSubset() }
                },
                onCancel: {
                    schemaConflict = nil
                }
            )
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
            if let resolved = originalItemType {
                if resolved.properties.isEmpty {
                    Text("No properties in this Item Type's schema.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(resolved.properties) { def in
                        PropertyEditorRow(
                            definition: def,
                            value: Binding(
                                get: { draftProperties[def.id] ?? .null },
                                set: { draftProperties[def.id] = $0 }
                            )
                        )
                    }
                }
            } else {
                Text("Item Type not found.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var relationsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Relations").font(.caption).foregroundStyle(.secondary)
            relationLine(label: "Tier 1 (Spaces)", ids: item.tier1)
            relationLine(label: "Tier 2 (Topics)", ids: item.tier2)
            relationLine(label: "Tier 3 (Sub-topics)", ids: item.tier3)
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
            .disabled(originalItemType == nil)
        }
        .padding()
    }

    // MARK: - State helpers

    private func hydrate() {
        draftTitle = item.title
        draftIcon = item.icon ?? ""
        draftDescription = item.description
        draftProperties = item.properties
        originalItemType = resolveItemType()
    }

    /// Scans ItemTypeManager to find the ItemType that contains this item.
    /// Matches by checking the item's ID against each type's loaded items
    /// in the content manager. Falls back to nil if not found (e.g., type
    /// was deleted while the window was in the sheet queue).
    private func resolveItemType() -> ItemType? {
        for type_ in itemTypeManager.types {
            // Check type-root items.
            let rootItems = itemContentManager.items(in: type_)
            if rootItems.contains(where: { $0.id == item.id }) {
                return type_
            }
            // Check collection-scoped items.
            for collection in itemTypeManager.itemCollections(in: type_) {
                let collItems = itemContentManager.items(in: collection)
                if collItems.contains(where: { $0.id == item.id }) {
                    return type_
                }
            }
        }
        return nil
    }

    // MARK: - Save with schema drift guard (EC4)

    private func save() async {
        guard !draftTitle.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Title can't be empty."
            return
        }

        guard let original = originalItemType else {
            errorMessage = "Item Type not found — cannot save."
            return
        }

        // 1. Re-fetch the current ItemType schema from disk.
        let metaURL = NexusPaths.itemTypeMetadataURL(
            in: itemContentManager.nexus.rootURL, typeFolderName: original.title
        )
        let freshType: ItemType
        do {
            freshType = try ItemType.load(from: metaURL)
        } catch {
            errorMessage = "Could not reload schema: \(error.localizedDescription)"
            return
        }

        // 2. Detect drift vs the user's pending edits.
        let drift = SchemaConflictDetector.detectDrift(
            editingProperties: draftProperties,
            freshSchema: freshType.properties,
            originalSchema: original.properties
        )

        // 3. If drift detected, surface the conflict dialog and return early.
        guard drift.removed.isEmpty && drift.typeChanged.isEmpty else {
            schemaConflict = SchemaConflictPayload(
                removed: drift.removed,
                typeChanged: drift.typeChanged
            )
            return
        }

        // 4. No drift — write the item.
        await commitSave(properties: draftProperties)
    }

    /// Called by the "Save valid subset" dialog action.
    private func saveValidSubset() async {
        guard let original = originalItemType else { return }

        let metaURL = NexusPaths.itemTypeMetadataURL(
            in: itemContentManager.nexus.rootURL, typeFolderName: original.title
        )
        let freshType = (try? ItemType.load(from: metaURL)) ?? original
        let filtered = SchemaConflictDetector.filterToValidSubset(
            editingProperties: draftProperties,
            freshSchema: freshType.properties
        )
        schemaConflict = nil
        await commitSave(properties: filtered)
    }

    /// Reload the item and schema from disk, replacing the editor's draft state.
    private func reloadFromDisk() {
        guard let original = originalItemType else { return }
        let folder = NexusPaths.itemTypeFolderURL(
            in: itemContentManager.nexus.rootURL, typeFolderName: original.title
        )
        let itemURL = NexusPaths.itemFileURL(forTitle: item.title, in: folder)
        guard let reloadedItem = try? Item.load(from: itemURL) else { return }
        draftTitle = reloadedItem.title
        draftIcon = reloadedItem.icon ?? ""
        draftDescription = reloadedItem.description
        draftProperties = reloadedItem.properties

        // Also refresh the originalItemType to the latest schema.
        let metaURL = NexusPaths.itemTypeMetadataURL(
            in: itemContentManager.nexus.rootURL, typeFolderName: original.title
        )
        if let freshType = try? ItemType.load(from: metaURL) {
            originalItemType = freshType
        }
        errorMessage = nil
    }

    /// Writes the item to disk using `ItemContentManager`.
    private func commitSave(properties: [String: PropertyValue]) async {
        var updated = item
        updated.title = draftTitle.trimmingCharacters(in: .whitespaces)
        updated.icon =
            draftIcon.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : draftIcon.trimmingCharacters(in: .whitespaces)
        updated.description = draftDescription
        updated.properties = properties

        guard let original = originalItemType else {
            errorMessage = "Item Type not found — cannot save."
            return
        }

        // Determine whether the item lives in a collection or at the type root.
        let collections = itemTypeManager.itemCollections(in: original)
        if let parentCollection = collections.first(where: { collection in
            itemContentManager.items(in: collection).contains { $0.id == item.id }
        }) {
            do {
                try await itemContentManager.updateItem(updated, in: parentCollection, type: original)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            do {
                try await itemContentManager.updateItem(updated, inTypeRoot: original)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func friendly(_ error: ItemValidator.ValidationError) -> String {
        switch error {
        case .emptyTitle: return "Title can't be empty."
        case .invalidTitleCharacters: return "Title can't contain / \\ :"
        case .descriptionTooLong: return "Description over 250 characters."
        case .tierMismatch: return "Internal: tier reference invalid."
        case .unknownProperty(let id): return "Unknown property '\(id)' for this Item Type."
        case .propertyTypeMismatch(let id): return "Property '\(id)' has wrong type."
        }
    }
}
