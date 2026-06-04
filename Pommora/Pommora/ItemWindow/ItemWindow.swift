import SwiftUI

struct ItemWindow: View {
    let item: Item
    let relationDisplay: RelationDisplayResolver
    @Environment(\.dismiss) private var dismiss

    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(ItemContentManager.self) private var itemContentManager

    @State private var draftTitle: String = ""
    @State private var draftIcon: String = ""
    @State private var draftDescription: String = ""
    @State private var draftProperties: [String: PropertyValue] = [:]
    @State private var errorMessage: String?

    /// The ItemType schema captured at open time — the baseline for drift detection.
    @State private var originalItemType: ItemType?

    /// Set when drift is detected on save; drives the SchemaConflictDialog sheet.
    @State private var schemaConflict: SchemaConflictPayload?

    // J.12: inspector panel state
    @State private var inspectorOpen: Bool = false

    /// The ItemCollection that contains this item (nil = type-root item).
    @State private var parentCollection: ItemCollection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            // J.12: pinned chips above title — only when in a collection and chips exist
            if let collection = parentCollection, !collection.pinnedProperties.isEmpty {
                pinnedChipsBar(collection: collection)
            }
            Divider()
            HStack(alignment: .top, spacing: 0) {
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
                // J.12: inspector side panel
                if inspectorOpen, let resolved = originalItemType {
                    Divider()
                    inspectorPanel(itemType: resolved)
                }
            }
            Divider()
            footer
        }
        .frame(
            width: inspectorOpen ? 760 : 480,
            height: 580
        )
        .animation(.easeInOut(duration: 0.2), value: inspectorOpen)
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

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: draftIcon.isEmpty ? "list.bullet.rectangle" : draftIcon)
                .font(.system(size: 20))
            Text(draftTitle).font(.headline)
            Spacer()
            // J.12: inspector toggle button
            Button {
                inspectorOpen.toggle()
            } label: {
                Image(systemName: inspectorOpen ? "sidebar.right" : "sidebar.right")
                    .symbolVariant(inspectorOpen ? .fill : .none)
                    .foregroundStyle(inspectorOpen ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help(inspectorOpen ? "Close Inspector" : "Open Inspector")
            .disabled(originalItemType == nil)
            Button("Done") { dismiss() }
        }
        .padding()
    }

    // MARK: - Pinned chips bar (J.12)

    private func pinnedChipsBar(collection: ItemCollection) -> some View {
        let validPinned = collection.pinnedProperties.filter { propID in
            originalItemType?.properties.first(where: { $0.id == propID }) != nil
        }
        return Group {
            if !validPinned.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(validPinned, id: \.self) { propID in
                            PinnedPropertyChip(
                                propID: propID,
                                schema: originalItemType?.properties ?? [],
                                values: draftProperties,
                                onUnpin: { unpin(propID: propID, from: collection) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .background(Color(.windowBackgroundColor).opacity(0.5))
            }
        }
    }

    // MARK: - Inspector side panel (J.12)

    private func inspectorPanel(itemType: ItemType) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Properties")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if itemType.properties.isEmpty {
                        Text("No properties defined.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(12)
                    } else {
                        ForEach(itemType.properties) { def in
                            PropertyEditorRow(
                                definition: def,
                                value: Binding(
                                    get: { draftProperties[def.id] ?? .null },
                                    set: { draftProperties[def.id] = $0 }
                                )
                            )
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            // J.12: right-click for "Pin to chips" — only in a collection
                            .contextMenu {
                                if let collection = parentCollection {
                                    Button {
                                        pin(propID: def.id, to: collection)
                                    } label: {
                                        Label("Pin to Chips", systemImage: "pin")
                                    }
                                }
                            }
                            Divider()
                                .padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
        .frame(width: 260)
    }

    // MARK: - Main form sections

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
                Text("\(draftDescription.count) / \(ItemValidator.maxDescriptionLength)")
                    .font(.caption)
                    .foregroundStyle(
                        draftDescription.count > ItemValidator.maxDescriptionLength
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
            RelationChipRow(label: "Spaces", ids: item.tier1, resolver: relationDisplay, labelWidth: 140)
            RelationChipRow(label: "Topics", ids: item.tier2, resolver: relationDisplay, labelWidth: 140)
            RelationChipRow(label: "Projects", ids: item.tier3, resolver: relationDisplay, labelWidth: 140)
        }
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
        parentCollection = resolveParentCollection()
    }

    private func resolveItemType() -> ItemType? {
        for type_ in itemTypeManager.types {
            let rootItems = itemContentManager.items(in: type_)
            if rootItems.contains(where: { $0.id == item.id }) {
                return type_
            }
            for collection in itemTypeManager.itemCollections(in: type_) {
                let collItems = itemContentManager.items(in: collection)
                if collItems.contains(where: { $0.id == item.id }) {
                    return type_
                }
            }
        }
        return nil
    }

    /// Returns the ItemCollection this item lives in, or nil if it's at type root.
    private func resolveParentCollection() -> ItemCollection? {
        for type_ in itemTypeManager.types {
            for collection in itemTypeManager.itemCollections(in: type_) {
                let collItems = itemContentManager.items(in: collection)
                if collItems.contains(where: { $0.id == item.id }) {
                    return collection
                }
            }
        }
        return nil
    }

    // MARK: - Pin / Unpin (J.12)

    /// Adds `propID` to `parentCollection.pinnedProperties` and persists to disk.
    private func pin(propID: String, to collection: ItemCollection) {
        guard !collection.pinnedProperties.contains(where: { $0 == propID }) else { return }
        var updated = collection
        updated.pinnedProperties.append(propID)
        persistCollection(updated)
    }

    /// Removes `propID` from `parentCollection.pinnedProperties` and persists.
    private func unpin(propID: String, from collection: ItemCollection) {
        var updated = collection
        updated.pinnedProperties.removeAll { $0 == propID }
        persistCollection(updated)
    }

    private func persistCollection(_ updated: ItemCollection) {
        guard let original = originalItemType else { return }
        let metaURL = NexusPaths.itemCollectionMetadataURL(
            in: itemContentManager.nexus.rootURL,
            typeFolderName: original.title,
            collectionFolderName: updated.title
        )
        do {
            try updated.save(to: metaURL)
            parentCollection = updated
        } catch {
            errorMessage = "Could not save collection: \(error.localizedDescription)"
        }
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

        let drift = SchemaConflictDetector.detectDrift(
            editingProperties: draftProperties,
            freshSchema: freshType.properties,
            originalSchema: original.properties
        )

        guard drift.removed.isEmpty && drift.typeChanged.isEmpty else {
            schemaConflict = SchemaConflictPayload(
                removed: drift.removed,
                typeChanged: drift.typeChanged
            )
            return
        }

        await commitSave(properties: draftProperties)
    }

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

    private func reloadFromDisk() {
        guard let original = originalItemType else { return }
        let folder = NexusPaths.itemTypeFolderURL(
            in: itemContentManager.nexus.rootURL, typeFolderName: original.title
        )
        let itemURL = NexusPaths.itemFileURL(forTitle: item.title, in: folder)
        // Lenient loader (matching the bulk read surface): it's a strict superset
        // of `Item.load` — for an id-less adopted `.md` Item where strict `load`
        // would throw, `loadLenient` synthesizes an id and surfaces it. Without it
        // the reload silently no-ops and the drifted draft persists.
        guard let reloadedItem = try? Item.loadLenient(from: itemURL)
        else { return }
        draftTitle = reloadedItem.title
        draftIcon = reloadedItem.icon ?? ""
        draftDescription = reloadedItem.description
        draftProperties = reloadedItem.properties

        let metaURL = NexusPaths.itemTypeMetadataURL(
            in: itemContentManager.nexus.rootURL, typeFolderName: original.title
        )
        if let freshType = try? ItemType.load(from: metaURL) {
            originalItemType = freshType
        }
        errorMessage = nil
    }

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

        let collections = itemTypeManager.itemCollections(in: original)
        do {
            if let parentCollection = collections.first(where: { collection in
                itemContentManager.items(in: collection).contains { $0.id == item.id }
            }) {
                try await itemContentManager.updateItem(updated, in: parentCollection, type: original)
            } else {
                try await itemContentManager.updateItem(updated, inTypeRoot: original)
            }
            dismiss()
        } catch {
            errorMessage = surface(error)
        }
    }

    /// Maps a save-path throw to a user-facing message, covering BOTH error
    /// domains the Item CRUD path can raise: `ItemValidator.ValidationError`
    /// (save-time schema/tier/description validation, surfaced via `friendly`)
    /// and `ItemCRUDError` / any other `LocalizedError` (title collisions,
    /// rename atomicity, IO) via its `localizedDescription`.
    private func surface(_ error: any Error) -> String {
        if let validation = error as? ItemValidator.ValidationError {
            return ItemValidator.friendly(validation)
        }
        return error.localizedDescription
    }
}

// MARK: - PinnedPropertyChip

/// Individual chip rendered in the pinned-properties bar. Right-click → Unpin.
private struct PinnedPropertyChip: View {
    let propID: String
    let schema: [PropertyDefinition]
    let values: [String: PropertyValue]
    let onUnpin: () -> Void

    private var definition: PropertyDefinition? {
        schema.first(where: { $0.id == propID })
    }

    var body: some View {
        Group {
            if let def = definition {
                chipView(def: def)
            }
        }
    }

    private func chipView(def: PropertyDefinition) -> some View {
        HStack(spacing: 4) {
            Text(def.name)
                .font(.caption)
                .foregroundStyle(.secondary)
            chipValue(def: def)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.controlBackgroundColor))
                .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
        )
        .contextMenu {
            Button(role: .destructive) {
                onUnpin()
            } label: {
                Label("Unpin", systemImage: "pin.slash")
            }
        }
    }

    @ViewBuilder
    private func chipValue(def: PropertyDefinition) -> some View {
        let val = values[def.id] ?? .null
        switch val {
        case .null:
            Text("—").font(.caption).foregroundStyle(.tertiary)
        case .checkbox(let b):
            Image(systemName: b ? "checkmark.square.fill" : "square")
                .font(.caption)
                .foregroundStyle(b ? Color.accentColor : .secondary)
        case .number(let n):
            Text(n.formatted()).font(.caption)
        case .select(let s):
            Text(s.isEmpty ? "—" : s).font(.caption)
        case .status(let s):
            Text(s.isEmpty ? "—" : s).font(.caption).foregroundStyle(.secondary)
        case .date(let d):
            Text(d.formatted(date: .abbreviated, time: .omitted)).font(.caption)
        case .datetime(let d):
            Text(d.formatted(date: .abbreviated, time: .shortened)).font(.caption)
        case .multiSelect(let xs):
            Text(xs.isEmpty ? "—" : xs.joined(separator: ", ")).font(.caption).lineLimit(1)
        case .url(let u):
            Text(u.host ?? u.absoluteString).font(.caption).lineLimit(1)
        case .relation:
            Text("→").font(.caption).foregroundStyle(.secondary)
        case .file(let refs):
            Text("\(refs.count) file(s)").font(.caption).foregroundStyle(.secondary)
        case .lastEditedTime:
            Text("auto").font(.caption).foregroundStyle(.tertiary)
        }
    }
}
