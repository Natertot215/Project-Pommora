import SwiftUI

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
///   - Relation (edit) → resolved read-only target + tier reverse rows
struct EditPropertyPane: View {
    let scope: ViewSettingsScope
    let propertyID: String
    @Binding var path: [ViewSettingsRoute]

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(\.dismiss) private var dismiss

    @State private var draftName: String = ""
    @State private var commitError: String?
    @State private var iconPickerOpen: Bool = false
    @State private var reverseIconPickerOpen: Bool = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        editBody
    }

    // MARK: - Edit-existing body

    @ViewBuilder
    private var editBody: some View {
        let def = currentDefinition()
        ViewSettingsPane {
            // Back affordance only ("‹ Edit Properties") + the property's own
            // icon + name field, which carries identity (no duplicate title).
            PaneHeader(path: $path, showsDivider: false)
            if let def {
                iconTitleRow(def: def)
                fieldDivider
            }
        } content: {
            if let def {
                VStack(alignment: .leading, spacing: PUI.Spacing.xl) {
                    middleSection(for: def)
                    if hasBottomPicker(for: def) {
                        // Display As / format scrolls WITH the options as a
                        // per-type setting — no divider above it, just the
                        // section spacing.
                        bottomPicker(for: def)
                    }
                }
                .padding(.horizontal, PUI.Pane.contentPadding)
                .padding(.vertical, PUI.Pane.contentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView(
                    "Property not found",
                    systemImage: "questionmark.circle",
                    description: Text("The property may have been deleted in another window.")
                )
            }
        } footer: {
            // Pinned bottom: ONLY the Delete / Duplicate footer (suppressed
            // for reserved properties such as the tier entries).
            if let def {
                bottomBlock(for: def)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if let def = currentDefinition() {
                draftName = def.name
            }
        }
    }

    /// Top-level divider between the icon/title field and the scroll body.
    /// Flush to the content rail (same horizontal inset as the field + scroll
    /// content), with breathing room above/below. NOT inset/squished.
    @ViewBuilder
    private var fieldDivider: some View {
        PaneDivider()
            .padding(.vertical, PUI.Pane.dividerPaddingVertical)
    }

    /// Bottom block pinned to the popover bottom (fixed regardless of
    /// middle-content height): just the lower divider + the Delete | Duplicate
    /// row, on the universal `PaneDivider` + "New property" footer rail (16h /
    /// 10v). Display As / format is NOT here — it scrolls with the options.
    ///
    /// Reserved properties (the tier entries `_tier1/2/3`) carry no
    /// Delete/Duplicate affordance — the footer collapses to error display
    /// only so the divider doesn't float over empty space.
    @ViewBuilder
    private func bottomBlock(for def: PropertyDefinition) -> some View {
        if !ReservedPropertyID.isReserved(def.id) {
            PaneDivider()
            footerRow(def: def)
                .padding(.horizontal, PUI.Pane.contentPadding)
                .padding(.vertical, PUI.Spacing.lg)
        } else if let err = commitError {
            PaneDivider()
            Text(err)
                .font(PUI.Typography.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, PUI.Pane.contentPadding)
                .padding(.vertical, PUI.Spacing.lg)
        }
    }

    // MARK: - Icon + name field row

    @ViewBuilder
    private func iconTitleRow(def: PropertyDefinition) -> some View {
        HStack(spacing: PUI.Row.interSpacing) {
            Button {
                iconPickerOpen = true
            } label: {
                Image(systemName: def.displayIcon)
                    .font(PUI.Icon.header)
                    .foregroundStyle(.primary)
                    .frame(width: PUI.Icon.headerFrame, height: PUI.Icon.headerFrame)
                    .fieldBackground()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit Icon")
            .disabled(ReservedPropertyID.isReserved(def.id))
            // Pommora-native IconPicker — a compact single-glass popover.
            .iconPickerPopover(isPresented: $iconPickerOpen, symbol: iconBinding)

            // Fixed-width: fills the content rail (so width is
            // content-independent); its trailing edge defines the rail the
            // section affordances ("Add") below right-align to.
            TextField("Property name", text: $draftName)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(.horizontal, PUI.Spacing.lg)
                .padding(.vertical, PUI.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fieldBackground()
                .focused($nameFocused)
                .onSubmit {
                    Task { await commitRename() }
                    nameFocused = false
                }
                .onChange(of: nameFocused) { wasFocused, isFocused in
                    // Commit on focus loss (click outside the TextField).
                    if wasFocused && !isFocused {
                        Task { await commitRename() }
                    }
                }
                // Safety net: dismissing the popover (outside-click) tears the
                // field down without a reliable blur — commit on disappear too.
                .onDisappear { Task { await commitRename() } }
                .disabled(ReservedPropertyID.isReserved(def.id))
        }
        .padding(.horizontal, PUI.Pane.contentPadding)
        .padding(.top, PUI.Spacing.xs)
        .padding(.bottom, PUI.Spacing.xs)
    }

    // MARK: - Middle (scrollable, per-type)

    @ViewBuilder
    private func middleSection(for def: PropertyDefinition) -> some View {
        switch def.type {
        case .select, .multiSelect:
            SelectOptionsEditor(
                options: bindingForSelectOptions(def: def),
                onAddOption: { Task { await addSelectOption() } }
            )
        case .status:
            StatusGroupsEditor(
                groups: bindingForStatusGroups(def: def),
                onAddOption: { groupID in
                    Task { await addStatusOption(in: groupID) }
                }
            )
        case .relation:
            relationEditSection(def: def)
        case .number, .date, .datetime, .checkbox, .url, .file, .lastEditedTime:
            EmptyView()
        }
    }

    // MARK: - Add option (Select / MultiSelect / Status)

    /// Mints a new Select / MultiSelect option with a default label.
    /// Commits via `updateProperty(transform:)`. The chip appears in the
    /// list; the user double-clicks to rename + color via the inline
    /// `OptionEditPopover` (no chevron-push navigation per Nathan's
    /// 2026-05-26 direction).
    private func addSelectOption() async {
        guard let typeID = parentTypeID() else { return }
        let newValue = "opt_\(ULID.generate())"
        let newOption = PropertyDefinition.SelectOption(
            value: newValue,
            label: "New option",
            color: nil
        )
        do {
            try await pageTypeManager.updateProperty(id: propertyID, in: typeID) { def in
                def.selectOptions = (def.selectOptions ?? []) + [newOption]
            }
            commitError = nil
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    /// Mints a new Status option inside the given group. User double-clicks
    /// the chip to rename + color via the inline `OptionEditPopover`.
    private func addStatusOption(in groupID: PropertyDefinition.StatusGroupID) async {
        guard let typeID = parentTypeID() else { return }
        let newValue = "opt_\(ULID.generate())"
        let newOption = PropertyDefinition.StatusOption(
            value: newValue,
            label: "New option",
            color: nil,
            groupID: groupID
        )
        do {
            try await pageTypeManager.updateProperty(id: propertyID, in: typeID) { def in
                var groups = def.statusGroups ?? []
                if let i = groups.firstIndex(where: { $0.id == groupID }) {
                    groups[i].options.append(newOption)
                }
                def.statusGroups = groups
            }
            commitError = nil
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    /// Edit-existing Relation section — the 2-row editor (Target + Reverse).
    ///   - Home: the icon + name field at the top of `editBody` (`iconTitleRow`),
    ///     edited via the existing rename/updateProperty path. NOT rendered here.
    ///   - Target: a LOCKED `⇄` + pill showing the resolved target (fixed at
    ///     creation; target cannot be changed after creation). For a tier entry it shows the tier label.
    ///   - Reverse: tier entries edit `reverseName` / `reverseIcon` live via
    ///     `applyTransform`.
    @ViewBuilder
    private func relationEditSection(def: PropertyDefinition) -> some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xl) {
            relationTargetReadonlyRow(def: def)
            relationTierReverseRows(def: def)
        }
    }

    /// Locked Target row: a leading `⇄` + a single `.fieldBackground()` pill
    /// containing the resolved target icon + label. Non-interactive — the target
    /// is fixed once the relation is created (a subtle `.help` says so). No
    /// caption, matching the clean 3-row mockup.
    @ViewBuilder
    private func relationTargetReadonlyRow(def: PropertyDefinition) -> some View {
        let resolved = resolvedTargetDisplay(def.relationTarget)
        HStack(spacing: PUI.Row.interSpacing) {
            Image(systemName: "arrow.left.arrow.right")
                .font(PUI.Icon.leading)
                .foregroundStyle(.secondary)
                .frame(width: PUI.Icon.headerFrame, height: PUI.Icon.headerFrame)

            HStack(spacing: PUI.Row.interSpacing) {
                Image(systemName: resolved.icon)
                    .font(PUI.Icon.leading)
                    .foregroundStyle(.secondary)
                    .frame(width: PUI.Icon.leadingFrame)
                Text(resolved.label)
                    .font(PUI.Typography.row)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, PUI.Spacing.lg)
            .padding(.vertical, PUI.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fieldBackground()
        }
        .help("The target is fixed once created.")
    }

    /// Tier-relation reverse editing: the Phase-3 `reverseName` (+ optional
    /// `reverseIcon`) live on the tier property itself.
    @ViewBuilder
    private func relationTierReverseRows(def: PropertyDefinition) -> some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
            Text("Reverse name")
                .font(PUI.Typography.sectionHeader)
                .foregroundStyle(.secondary)
            HStack(spacing: PUI.Row.interSpacing) {
                Button {
                    reverseIconPickerOpen = true
                } label: {
                    Image(systemName: def.reverseIcon ?? def.icon ?? PropertyType.relation.pickerIcon)
                        .font(PUI.Icon.leading)
                        .foregroundStyle(.secondary)
                        .frame(width: PUI.Icon.headerFrame, height: PUI.Icon.headerFrame)
                        .fieldBackground()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Change reverse icon")
                .iconPickerPopover(isPresented: $reverseIconPickerOpen, symbol: reverseIconBinding)

                TextField("Reverse name on the Context", text: bindingForReverseName(def: def))
                    .textFieldStyle(.plain)
                    .font(PUI.Typography.row)
                    .padding(.horizontal, PUI.Spacing.lg)
                    .padding(.vertical, PUI.Spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fieldBackground()
            }
            Text("Shown on the Context side of this tier relation.")
                .font(PUI.Typography.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// Resolves a stored relation target to a display (icon + label) for the
    /// read-only edit row. Tier targets map to their fixed tier label; anything
    /// unresolvable shows a neutral fallback.
    private func resolvedTargetDisplay(
        _ target: PropertyDefinition.RelationTarget?
    ) -> (icon: String, label: String) {
        switch target {
        case .some(.contextTier(let tier)):
            switch tier {
            case 1: return ("square.stack.3d.up", "Areas")
            case 2: return ("folder", "Topics")
            default: return ("list.bullet.rectangle", "Projects")
            }
        case .some:
            return ("arrow.triangle.branch", "Unknown target")
        case .none:
            return ("arrow.triangle.branch", "No target")
        }
    }

    // MARK: - Relation edit bindings (tier reverse only)

    /// Edit-mode binding for a tier relation's `reverseIcon` override.
    private var reverseIconBinding: Binding<String?> {
        Binding(
            get: { currentDefinition()?.reverseIcon },
            set: { newIcon in
                Task { await applyTransform { $0.reverseIcon = newIcon } }
            }
        )
    }

    private func bindingForReverseName(def: PropertyDefinition) -> Binding<String> {
        Binding(
            get: { currentDefinition()?.reverseName ?? "" },
            set: { newName in
                Task {
                    await applyTransform { transformee in
                        let trimmed = newName.trimmingCharacters(in: .whitespaces)
                        transformee.reverseName = trimmed.isEmpty ? nil : trimmed
                    }
                }
            }
        )
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
        case .date, .datetime:
            // Unified Date type: date-portion format + time-portion display.
            VStack(alignment: .leading, spacing: PUI.Spacing.xl) {
                dateFormatPicker(def: def)
                timeFormatPicker(def: def)
            }
        default: EmptyView()
        }
    }

    @ViewBuilder
    private func displayAsPicker(def: PropertyDefinition) -> some View {
        LabeledMenuSelector(title: "Display As", value: displayAsLabel(def.displayAs)) {
            Picker("Display As", selection: displayAsSelectionBinding(def: def)) {
                Text("Box").tag(DisplayVariant.box)
                Text("Select").tag(DisplayVariant.select)
                Text("Chip").tag(DisplayVariant.chip)
            }
        }
    }

    @ViewBuilder
    private func numberFormatPicker(def: PropertyDefinition) -> some View {
        LabeledMenuSelector(title: "Format", value: (def.numberFormat ?? .decimal).rawValue.capitalized) {
            Picker("Format", selection: bindingForNumberFormat(def: def)) {
                ForEach(PropertyDefinition.NumberFormat.allCases, id: \.self) { fmt in
                    Text(fmt.rawValue.capitalized).tag(fmt)
                }
            }
        }
    }

    /// Date-portion display format. No "Default" row — always a concrete pick
    /// (nil reads as `.long`).
    @ViewBuilder
    private func dateFormatPicker(def: PropertyDefinition) -> some View {
        LabeledMenuSelector(title: "Display Date", value: (def.dateFormat ?? .full).displayLabel) {
            Picker("Display Date", selection: bindingForDateFormat(def: def)) {
                ForEach(DateFormat.allCases, id: \.self) { fmt in
                    Text(fmt.displayLabel).tag(fmt)
                }
            }
        }
    }

    /// Time-portion display: None (date only) / 12 Hour / 24 Hour. nil reads as
    /// `.none`.
    @ViewBuilder
    private func timeFormatPicker(def: PropertyDefinition) -> some View {
        LabeledMenuSelector(title: "Display Time", value: (def.timeFormat ?? .none).displayLabel) {
            Picker("Display Time", selection: bindingForTimeFormat(def: def)) {
                ForEach(TimeFormat.allCases, id: \.self) { fmt in
                    Text(fmt.displayLabel).tag(fmt)
                }
            }
        }
    }

    private func displayAsLabel(_ variant: DisplayVariant?) -> String {
        switch variant {
        case .box: return "Box"
        case .chip: return "Chip"
        case .select, .none: return "Select"
        }
    }

    // MARK: - Pinned footer (Delete | Duplicate, borderless mini-buttons)

    @ViewBuilder
    private func footerRow(def: PropertyDefinition) -> some View {
        // Placement (horizontal + vertical) is owned by `bottomBlock`, which
        // pins this row to the popover bottom on the standard rail and only
        // renders this row for non-reserved properties (tier entries get no
        // Delete/Duplicate affordance at all).
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
        }

        if let err = commitError {
            Text(err)
                .font(PUI.Typography.caption)
                .foregroundStyle(.red)
                .padding(.bottom, PUI.Row.paddingVertical)
        }
    }

    // MARK: - Lookups

    private func currentDefinition() -> PropertyDefinition? {
        guard let typeID = parentTypeID() else { return nil }
        return pageTypeManager.types
            .first(where: { $0.id == typeID })?
            .properties.first(where: { $0.id == propertyID })
    }

    private func parentTypeID() -> String? { scope.schemaTypeID }

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

    private func bindingForDateFormat(def: PropertyDefinition) -> Binding<DateFormat> {
        Binding(
            get: { def.dateFormat ?? .full },
            set: { newValue in
                Task {
                    await applyTransform { $0.dateFormat = newValue }
                }
            }
        )
    }

    private func bindingForTimeFormat(def: PropertyDefinition) -> Binding<TimeFormat> {
        Binding(
            get: { def.timeFormat ?? .none },
            set: { newValue in
                Task {
                    await applyTransform { $0.timeFormat = newValue }
                }
            }
        )
    }

    /// Non-optional selection binding for the Display As inline Picker — nil
    /// (implicit) reads as `.select` so the checkmark lands on the right row.
    private func displayAsSelectionBinding(def: PropertyDefinition) -> Binding<DisplayVariant> {
        Binding(
            get: { def.displayAs ?? .select },
            set: { newValue in
                Task {
                    // `.select` is the implicit (nil) default — persist nil for
                    // it so re-selecting the default doesn't write a spurious
                    // explicit value (preserves the nil-default on-disk contract).
                    await applyTransform { $0.displayAs = (newValue == .select) ? nil : newValue }
                }
            }
        )
    }

    // MARK: - Commits

    private func applyTransform(_ transform: @escaping (inout PropertyDefinition) -> Void) async {
        guard let typeID = parentTypeID() else { return }
        do {
            try await pageTypeManager.updateProperty(id: propertyID, in: typeID, transform: transform)
            commitError = nil
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    private func commitRename() async {
        guard let typeID = parentTypeID() else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        // Skip empty + no-op renames so Enter / blur / disappear can all fire
        // without double-writing or clobbering with an unchanged value.
        guard !trimmed.isEmpty, trimmed != currentDefinition()?.name else { return }
        do {
            try await pageTypeManager.renameProperty(id: propertyID, in: typeID, to: trimmed)
            commitError = nil
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    private func commitDelete() async {
        guard let typeID = parentTypeID() else { return }
        // Pop FIRST, then await the disk delete. If we awaited delete first,
        // the manager's `types` array mutates while this pane is still
        // mounted; the body re-renders against `currentDefinition() == nil`
        // and SwiftUI flashes "Property not found" before the pop unmounts
        // the pane. Pop-first sidesteps the dangling render entirely — the
        // disk delete completes off-screen.
        if !path.isEmpty { path.removeLast() }
        do {
            try await pageTypeManager.deleteProperty(id: propertyID, in: typeID)
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    private func commitDuplicate() async {
        guard let typeID = parentTypeID() else { return }
        do {
            try await pageTypeManager.duplicateProperty(id: propertyID, in: typeID)
            if !path.isEmpty { path.removeLast() }
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }
}
