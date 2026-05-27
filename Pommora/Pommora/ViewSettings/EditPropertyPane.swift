import SwiftUI
import SymbolPicker

/// View Settings → Edit Properties → per-property editor.
///
/// Layout per Figma (node V3wKMilXkoceCL1Q2J9kf4 / 474:9432):
///
/// ```
/// ┌─────────────────────────────────────┐
/// │ < Edit Property        (PaneHeader) │
/// │ ─────                               │
/// │ [icon]  [name TextField, plain]     │  header row — icon Button opens SymbolPicker
/// │ ─────                               │
/// │  <scrollable per-type middle>       │  Status groups, Select options, Relation scope, etc.
/// │                                     │
/// │ ─────                               │
/// │ Display As            Chip ▾        │  pinned bottom picker (Status only at first ship;
/// │                                     │     Number/Date use their format picker here)
/// │ ─────                               │
/// │ Delete            Duplicate         │  pinned footer: borderless mini-buttons,
/// └─────────────────────────────────────┘     Delete on the left (red), Duplicate on the right
/// ```
///
/// **Key design rules** (per Nathan, locked 2026-05-26):
/// - Icon at top renders the property's current icon (defaults to the type's
///   pickerIcon when unset) and is a tappable Button — opens `SymbolPicker`
///   for icon selection.
/// - Title TextField uses `.plain` style — no rounded-border ring, no blue
///   focus emphasis.
/// - Delete + Duplicate footer is PINNED to the pane bottom (not inline in
///   the scroll body) and renders as borderless side-by-side mini-buttons
///   with no icons.
/// - Display As / Format pickers PINNED above the footer as Label-Menu rows.
/// - Type-label row is removed — the icon at top conveys the type.
///
/// Live-save model unchanged: rename commits via `renameProperty`; per-config
/// edits commit via `updateProperty(id:in:transform:)`; icon updates flow
/// through the same `updateProperty` transform.
///
/// Per-type sections:
///   - Select / MultiSelect → `SelectOptionsEditor` in scroll body, no bottom picker
///   - Status → `StatusGroupsEditor` in scroll body + Display As pinned bottom
///   - Date / DateTime → empty middle + Date Format pinned bottom
///   - Number → empty middle + Number Format pinned bottom
///   - URL / File / Checkbox → empty middle, no bottom picker
///   - Relation → read-only scope summary in scroll body, no bottom picker
struct EditPropertyPane: View {
    let scope: ViewSettingsScope
    let propertyID: String
    @Binding var path: [ViewSettingsRoute]

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(\.dismiss) private var dismiss

    @State private var draftName: String = ""
    @State private var commitError: String?
    @State private var iconPickerOpen: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(path: $path, title: "Edit Property")

            if let def = currentDefinition() {
                headerRow(def: def)
                Divider()

                ScrollView {
                    middleSection(for: def)
                        .padding(.horizontal, PUI.Pane.contentPadding)
                        .padding(.vertical, PUI.Pane.contentPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)

                if hasBottomPicker(for: def) {
                    Divider()
                    bottomPicker(for: def)
                        .padding(.horizontal, PUI.Row.paddingHorizontal)
                        .padding(.vertical, PUI.Row.paddingVertical)
                }

                Divider()
                footerRow(def: def)
            } else {
                ContentUnavailableView(
                    "Property not found",
                    systemImage: "questionmark.circle",
                    description: Text("The property may have been deleted in another window.")
                )
                .frame(maxHeight: .infinity)
            }
        }
        .frame(width: PUI.Pane.width, height: PUI.Pane.height)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if let def = currentDefinition() { draftName = def.name }
        }
        .sheet(isPresented: $iconPickerOpen) {
            SymbolPicker(symbol: iconBinding)
        }
    }

    // MARK: - Header (icon Button + plain TextField)

    @ViewBuilder
    private func headerRow(def: PropertyDefinition) -> some View {
        HStack(spacing: PUI.Row.interSpacing) {
            Button {
                iconPickerOpen = true
            } label: {
                Image(systemName: def.icon ?? def.type.pickerIcon)
                    .font(PUI.Icon.header)
                    .foregroundStyle(.primary)
                    .frame(width: PUI.Icon.headerFrame, height: PUI.Icon.headerFrame)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Change icon")
            .disabled(ReservedPropertyID.isReserved(def.id))

            TextField("Property name", text: $draftName)
                .textFieldStyle(.plain)
                .font(PUI.Typography.row)
                .onSubmit { Task { await commitRename() } }
                .disabled(ReservedPropertyID.isReserved(def.id))
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)
    }

    // MARK: - Middle (scrollable, per-type)

    @ViewBuilder
    private func middleSection(for def: PropertyDefinition) -> some View {
        switch def.type {
        case .select, .multiSelect:
            SelectOptionsEditor(options: bindingForSelectOptions(def: def))
        case .status:
            StatusGroupsEditor(groups: bindingForStatusGroups(def: def))
        case .relation:
            relationScopeSummary(def: def)
        case .number, .date, .datetime, .checkbox, .url, .file, .lastEditedTime:
            EmptyView()
        }
    }

    @ViewBuilder
    private func relationScopeSummary(def: PropertyDefinition) -> some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
            Text("Scope")
                .font(PUI.Typography.sectionHeader)
                .foregroundStyle(.secondary)
            Text(relationScopeText(def.relationScope))
                .font(PUI.Typography.row)
                .foregroundStyle(.primary)
            Text("Change scope from Vault Settings → Edit Properties (v0.3.1.5).")
                .font(PUI.Typography.caption)
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

    // MARK: - Pinned bottom picker (Status / Number / Date)

    private func hasBottomPicker(for def: PropertyDefinition) -> Bool {
        switch def.type {
        case .status, .number, .date, .datetime: return true
        case .select, .multiSelect, .checkbox, .url, .file, .relation, .lastEditedTime: return false
        }
    }

    @ViewBuilder
    private func bottomPicker(for def: PropertyDefinition) -> some View {
        switch def.type {
        case .status: displayAsPicker(def: def)
        case .number: numberFormatPicker(def: def)
        case .date, .datetime: dateFormatPicker(def: def)
        default: EmptyView()
        }
    }

    @ViewBuilder
    private func displayAsPicker(def: PropertyDefinition) -> some View {
        HStack(spacing: PUI.Spacing.md) {
            Text("Display As")
                .font(PUI.Typography.row)
                .foregroundStyle(.primary)
            Spacer()
            Picker("Display As", selection: bindingForDisplayAs(def: def)) {
                Text("Box").tag(DisplayVariant?.some(.box))
                Text("Select").tag(DisplayVariant?.some(.select))
                Text("Chip").tag(DisplayVariant?.some(.chip))
                Divider()
                Text("Default").tag(DisplayVariant?.none)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func numberFormatPicker(def: PropertyDefinition) -> some View {
        HStack(spacing: PUI.Spacing.md) {
            Text("Format")
                .font(PUI.Typography.row)
                .foregroundStyle(.primary)
            Spacer()
            Picker("Format", selection: bindingForNumberFormat(def: def)) {
                ForEach(PropertyDefinition.NumberFormat.allCases, id: \.self) { fmt in
                    Text(fmt.rawValue.capitalized).tag(fmt)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func dateFormatPicker(def: PropertyDefinition) -> some View {
        HStack(spacing: PUI.Spacing.md) {
            Text("Display as")
                .font(PUI.Typography.row)
                .foregroundStyle(.primary)
            Spacer()
            Picker("Display as", selection: bindingForDateFormat(def: def)) {
                Text("Default").tag(DateFormat?.none)
                ForEach(DateFormat.allCases, id: \.self) { fmt in
                    Text(dateFormatLabel(fmt)).tag(DateFormat?.some(fmt))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private func dateFormatLabel(_ fmt: DateFormat) -> String {
        switch fmt {
        case .monthDayLong: return "March 4"
        case .monthDayYearLong: return "March 4, 2026"
        case .numericShort: return "03-04"
        case .numericMedium: return "03-04-26"
        case .numericLong: return "03-04-2026"
        case .iso: return "2026-03-04"
        }
    }

    // MARK: - Pinned footer (Delete | Duplicate, borderless mini-buttons)

    @ViewBuilder
    private func footerRow(def: PropertyDefinition) -> some View {
        HStack(spacing: 0) {
            Button(role: .destructive) {
                Task { await commitDelete() }
            } label: {
                Text("Delete")
                    .font(PUI.Typography.row)
                    .foregroundStyle(.red)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(ReservedPropertyID.isReserved(def.id))

            Spacer()

            Button {
                Task { await commitDuplicate() }
            } label: {
                Text("Duplicate")
                    .font(PUI.Typography.row)
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(ReservedPropertyID.isReserved(def.id))
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)

        if let err = commitError {
            Text(err)
                .font(PUI.Typography.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, PUI.Row.paddingHorizontal)
                .padding(.bottom, PUI.Row.paddingVertical)
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

    // MARK: - Bindings

    private var iconBinding: Binding<String?> {
        Binding(
            get: { currentDefinition()?.icon },
            set: { newIcon in
                Task { await applyTransform { $0.icon = newIcon } }
            }
        )
    }

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
            if !path.isEmpty { path.removeLast() }
        } catch {
            commitError = String(describing: error)
        }
    }
}
