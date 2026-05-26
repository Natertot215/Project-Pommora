import SwiftUI

/// View Settings → Edit Properties → per-property editor.
///
/// Notion-style structure: header row (icon + inline name field) + Type row
/// (read-only at v0.3.1; change-type pushes to v0.3.1.5) + type-aware middle
/// section + footer (Delete property). Duplicate property lands at Task 11b.
///
/// Live-save model: rename commits via `renameProperty(id:in:to:)`; per-config
/// edits (select options, status groups, displayAs, dateFormat, numberFormat,
/// accept) commit via `updateProperty(id:in:transform:)` (extension on each
/// manager). All commits flow through the parent Type's manager — for
/// Collection scopes we look up the parent via `typeID`.
///
/// Per-type middle sections (locked decisions):
///   - Select / MultiSelect → SelectOptionsEditor (shared from Task 8)
///   - Status → DisplayVariant Picker + StatusGroupsEditor (shared from Task 8)
///   - Date / DateTime → DateFormatPicker (Display as)
///   - Number → NumberFormatPicker (shared from Task 8)
///   - URL / File / Checkbox → no middle section (rename-only)
///   - Relation → read-only scope summary
///   - LastEditedTime → reserved; pane shouldn't be reachable for it
///     (PropertiesListPane disables the chevron on reserved properties).
struct EditPropertyPane: View {
    let scope: ViewSettingsScope
    let propertyID: String
    @Binding var path: [ViewSettingsRoute]

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(\.dismiss) private var dismiss

    @State private var draftName: String = ""
    @State private var commitError: String?

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(path: $path, title: "Edit Property")

            Group {
                if let def = currentDefinition() {
                    ScrollView {
                        VStack(alignment: .leading, spacing: PUI.Spacing.xxl) {
                            headerRow(def: def)
                            typeRow(def: def)
                            middleSection(for: def)
                            footer(def: def)
                        }
                        .padding(.horizontal, PUI.Pane.contentPadding)
                        .padding(.vertical, PUI.Pane.contentPadding)
                    }
                } else {
                    ContentUnavailableView(
                        "Property not found",
                        systemImage: "questionmark.circle",
                        description: Text("The property may have been deleted in another window.")
                    )
                }
            }
        }
        .frame(width: PUI.Pane.width, height: PUI.Pane.height)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if let def = currentDefinition() { draftName = def.name }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func headerRow(def: PropertyDefinition) -> some View {
        HStack(spacing: 8) {
            Image(systemName: def.icon ?? def.type.pickerIcon)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 22, height: 22)
            TextField("Property name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .onSubmit { Task { await commitRename() } }
        }
    }

    @ViewBuilder
    private func typeRow(def: PropertyDefinition) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "tag")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text("Type")
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer()
            Text(def.type.displayName)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .help("Type changes for existing properties land at v0.3.1.5")
    }

    @ViewBuilder
    private func middleSection(for def: PropertyDefinition) -> some View {
        Divider()
        switch def.type {
        case .select, .multiSelect:
            SelectOptionsEditor(options: bindingForSelectOptions(def: def))
        case .status:
            VStack(alignment: .leading, spacing: 12) {
                displayVariantRow(def: def)
                StatusGroupsEditor(groups: bindingForStatusGroups(def: def))
            }
        case .date, .datetime:
            DateFormatPicker(format: bindingForDateFormat(def: def))
        case .number:
            NumberFormatPicker(format: bindingForNumberFormat(def: def))
        case .url, .file, .checkbox:
            EmptyView()
        case .relation:
            relationScopeSummary(def: def)
        case .lastEditedTime:
            EmptyView()  // reserved; not reachable
        }
    }

    @ViewBuilder
    private func displayVariantRow(def: PropertyDefinition) -> some View {
        HStack(spacing: 8) {
            Text("Display as")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("Display as", selection: bindingForDisplayAs(def: def)) {
                Text("Box").tag(DisplayVariant?.some(.box))
                Text("Select").tag(DisplayVariant?.some(.select))
                Text("Chip").tag(DisplayVariant?.some(.chip))
                Divider()
                Text("Default (.box)").tag(DisplayVariant?.none)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 130)
        }
    }

    @ViewBuilder
    private func relationScopeSummary(def: PropertyDefinition) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Scope")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(relationScopeText(def.relationScope))
                .font(.callout)
                .foregroundStyle(.primary)
            Text("Change scope from Vault Settings → Edit Properties (v0.3.1.5).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func relationScopeText(_ scope: PropertyDefinition.RelationScope?) -> String {
        switch scope {
        case .pageType(let id): return "Page Type \(id.prefix(8))…"
        case .itemType(let id): return "Item Type \(id.prefix(8))…"
        case .pageCollection(let id): return "Page Collection \(id.prefix(8))…"
        case .itemCollection(let id): return "Item Collection \(id.prefix(8))…"
        case .contextTier(let tier): return "Context tier \(tier)"
        case .none: return "Unset"
        }
    }

    @ViewBuilder
    private func footer(def: PropertyDefinition) -> some View {
        Divider()
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Task { await commitDuplicate() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .frame(width: 18)
                    Text("Duplicate property")
                        .font(.callout)
                    Spacer()
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(ReservedPropertyID.isReserved(def.id))

            Button(role: .destructive) {
                Task { await commitDelete() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .frame(width: 18)
                    Text("Delete property")
                        .font(.callout)
                    Spacer()
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .disabled(ReservedPropertyID.isReserved(def.id))
        }

        if let err = commitError {
            Text(err)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Lookups

    private func currentDefinition() -> PropertyDefinition? {
        guard let typeID = parentTypeID() else { return nil }
        switch scope {
        case .pageType, .pageCollection:
            return pageTypeManager.types
                .first(where: { $0.id == typeID })?
                .properties.first(where: { $0.id == propertyID })
        case .itemType, .itemCollection:
            return itemTypeManager.types
                .first(where: { $0.id == typeID })?
                .properties.first(where: { $0.id == propertyID })
        default:
            return nil
        }
    }

    private func parentTypeID() -> String? {
        switch scope {
        case .pageType(let t): return t.id
        case .itemType(let t): return t.id
        case .pageCollection(let c): return c.typeID
        case .itemCollection(let c): return c.typeID
        default: return nil
        }
    }

    private enum SideKind {
        case pages
        case items
    }

    private var side: SideKind? {
        switch scope {
        case .pageType, .pageCollection: return .pages
        case .itemType, .itemCollection: return .items
        default: return nil
        }
    }

    // MARK: - Per-config Bindings

    private func bindingForSelectOptions(def: PropertyDefinition) -> Binding<[PropertyDefinition.SelectOption]> {
        Binding(
            get: { def.selectOptions ?? [] },
            set: { newValue in
                Task {
                    await applyTransform { $0.selectOptions = newValue }
                }
            }
        )
    }

    private func bindingForStatusGroups(def: PropertyDefinition) -> Binding<[PropertyDefinition.StatusGroup]> {
        Binding(
            get: { def.statusGroups ?? [] },
            set: { newValue in
                Task {
                    await applyTransform { $0.statusGroups = newValue }
                }
            }
        )
    }

    private func bindingForNumberFormat(def: PropertyDefinition) -> Binding<PropertyDefinition.NumberFormat> {
        Binding(
            get: { def.numberFormat ?? .decimal },
            set: { newValue in
                Task {
                    await applyTransform { $0.numberFormat = newValue }
                }
            }
        )
    }

    private func bindingForDateFormat(def: PropertyDefinition) -> Binding<DateFormat?> {
        Binding(
            get: { def.dateFormat },
            set: { newValue in
                Task {
                    await applyTransform { $0.dateFormat = newValue }
                }
            }
        )
    }

    private func bindingForDisplayAs(def: PropertyDefinition) -> Binding<DisplayVariant?> {
        Binding(
            get: { def.displayAs },
            set: { newValue in
                Task {
                    await applyTransform { $0.displayAs = newValue }
                }
            }
        )
    }

    // MARK: - Commits

    private func applyTransform(_ transform: @escaping (inout PropertyDefinition) -> Void) async {
        guard let typeID = parentTypeID(), let side else { return }
        do {
            switch side {
            case .pages:
                try await pageTypeManager.updateProperty(id: propertyID, in: typeID, transform: transform)
            case .items:
                try await itemTypeManager.updateProperty(id: propertyID, in: typeID, transform: transform)
            }
            commitError = nil
        } catch {
            commitError = String(describing: error)
        }
    }

    private func commitRename() async {
        guard let typeID = parentTypeID(), let side else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            switch side {
            case .pages:
                try await pageTypeManager.renameProperty(id: propertyID, in: typeID, to: trimmed)
            case .items:
                try await itemTypeManager.renameProperty(id: propertyID, in: typeID, to: trimmed)
            }
            commitError = nil
        } catch {
            commitError = String(describing: error)
        }
    }

    private func commitDelete() async {
        guard let typeID = parentTypeID(), let side else { return }
        // Pop FIRST, then await the disk delete. If we awaited delete first,
        // the manager's `types` array mutates while this pane is still
        // mounted; the body re-renders against `currentDefinition() == nil`
        // and SwiftUI flashes "Property not found" before the pop unmounts
        // the pane. Pop-first sidesteps the dangling render entirely — the
        // disk delete completes off-screen.
        if !path.isEmpty { path.removeLast() }
        do {
            switch side {
            case .pages:
                try await pageTypeManager.deleteProperty(id: propertyID, in: typeID)
            case .items:
                try await itemTypeManager.deleteProperty(id: propertyID, in: typeID)
            }
        } catch {
            // Pane is already unmounted; surface the error via the manager's
            // pendingError toast pathway (set by deleteProperty on failure).
            commitError = String(describing: error)
        }
    }

    private func commitDuplicate() async {
        guard let typeID = parentTypeID(), let side else { return }
        do {
            switch side {
            case .pages:
                try await pageTypeManager.duplicateProperty(id: propertyID, in: typeID)
            case .items:
                try await itemTypeManager.duplicateProperty(id: propertyID, in: typeID)
            }
            // Pop back to the Properties list so the user can see the new copy.
            if !path.isEmpty { path.removeLast() }
        } catch {
            commitError = String(describing: error)
        }
    }
}
