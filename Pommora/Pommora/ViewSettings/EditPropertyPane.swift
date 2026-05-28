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
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Back affordance only ("‹ Edit Properties"). The property's own
            // icon + name field below carries identity — no duplicate title.
            PaneHeader(path: $path, showsDivider: false)

            if let def = currentDefinition() {
                iconTitleRow(def: def)
                fieldDivider

                // Flexible middle: the per-type editor (Options list, etc.)
                // scrolls + absorbs all spare height.
                ScrollView {
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
                }
                .frame(maxHeight: .infinity)

                // Pinned bottom: ONLY the Delete / Duplicate footer.
                bottomBlock(for: def)
            } else {
                ContentUnavailableView(
                    "Property not found",
                    systemImage: "questionmark.circle",
                    description: Text("The property may have been deleted in another window.")
                )
                .frame(maxHeight: .infinity)
            }
        }
        .measuredPaneHeight()
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if let def = currentDefinition() { draftName = def.name }
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
    @ViewBuilder
    private func bottomBlock(for def: PropertyDefinition) -> some View {
        PaneDivider()
        footerRow(def: def)
            .padding(.horizontal, PUI.Pane.contentPadding)
            .padding(.vertical, PUI.Spacing.lg)
    }

    // MARK: - Icon + name field row

    @ViewBuilder
    private func iconTitleRow(def: PropertyDefinition) -> some View {
        HStack(spacing: PUI.Row.interSpacing) {
            Button {
                iconPickerOpen = true
            } label: {
                Image(systemName: def.icon ?? def.type.pickerIcon)
                    .font(PUI.Icon.header)
                    .foregroundStyle(.primary)
                    .frame(width: PUI.Icon.headerFrame, height: PUI.Icon.headerFrame)
                    .fieldBackground()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Change icon")
            .disabled(ReservedPropertyID.isReserved(def.id))
            // Anchored popover replaces the third-party SymbolPicker's
            // default full-screen sheet. Frame sized to fit its grid +
            // section sidebar without clipping.
            .popover(isPresented: $iconPickerOpen, arrowEdge: .bottom) {
                SymbolPicker(symbol: iconBinding)
                    .frame(width: 540, height: 460)
            }

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
            relationScopeSummary(def: def)
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
        guard let typeID = parentTypeID(), let side else { return }
        let newValue = "opt_\(ULID.generate())"
        let newOption = PropertyDefinition.SelectOption(
            value: newValue,
            label: "New option",
            color: nil
        )
        do {
            switch side {
            case .pages:
                try await pageTypeManager.updateProperty(id: propertyID, in: typeID) { def in
                    def.selectOptions = (def.selectOptions ?? []) + [newOption]
                }
            case .items:
                try await itemTypeManager.updateProperty(id: propertyID, in: typeID) { def in
                    def.selectOptions = (def.selectOptions ?? []) + [newOption]
                }
            }
            commitError = nil
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    /// Mints a new Status option inside the given group. User double-clicks
    /// the chip to rename + color via the inline `OptionEditPopover`.
    private func addStatusOption(in groupID: PropertyDefinition.StatusGroupID) async {
        guard let typeID = parentTypeID(), let side else { return }
        let newValue = "opt_\(ULID.generate())"
        let newOption = PropertyDefinition.StatusOption(
            value: newValue,
            label: "New option",
            color: nil,
            groupID: groupID
        )
        do {
            switch side {
            case .pages:
                try await pageTypeManager.updateProperty(id: propertyID, in: typeID) { def in
                    var groups = def.statusGroups ?? []
                    if let i = groups.firstIndex(where: { $0.id == groupID }) {
                        groups[i].options.append(newOption)
                    }
                    def.statusGroups = groups
                }
            case .items:
                try await itemTypeManager.updateProperty(id: propertyID, in: typeID) { def in
                    var groups = def.statusGroups ?? []
                    if let i = groups.firstIndex(where: { $0.id == groupID }) {
                        groups[i].options.append(newOption)
                    }
                    def.statusGroups = groups
                }
            }
            commitError = nil
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    /// Minimal Relation editor (v0.3.1.0.2):
    ///   - Scope kind: Picker (5 cases)
    ///   - Target ID: TextField (for container scopes) OR tier Picker (for
    ///     contextTier)
    ///   - Mirror name: TextField (non-context only; stored as
    ///     `dualProperty.syncedPropertyID` per the wizard's at-add convention)
    ///   - Allows multiple: Toggle
    ///
    /// Full paired-relation creation (DualRelationCoordinator) is deferred
    /// — this editor writes the relation metadata, but the reverse property
    /// on the target Type is not yet auto-minted. That arrives with the
    /// searchable target picker in a later slice.
    @ViewBuilder
    private func relationScopeSummary(def: PropertyDefinition) -> some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.lg) {
            relationKindRow(def: def)
            relationTargetRow(def: def)
            if !isContextTierScope(def.relationScope) {
                relationMirrorRow(def: def)
            }
            relationAllowsMultipleRow(def: def)
        }
    }

    @ViewBuilder
    private func relationKindRow(def: PropertyDefinition) -> some View {
        HStack(spacing: PUI.Spacing.md) {
            Text("Scope")
                .font(PUI.Typography.row)
                .foregroundStyle(.primary)
            Spacer()
            Picker("Scope", selection: bindingForRelationKind(def: def)) {
                Text("Unset").tag(RelationScopeKind?.none)
                Text("Page Type").tag(RelationScopeKind?.some(.pageType))
                Text("Item Type").tag(RelationScopeKind?.some(.itemType))
                Text("Page Collection").tag(RelationScopeKind?.some(.pageCollection))
                Text("Item Collection").tag(RelationScopeKind?.some(.itemCollection))
                Text("Context Tier").tag(RelationScopeKind?.some(.contextTier))
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func relationTargetRow(def: PropertyDefinition) -> some View {
        if isContextTierScope(def.relationScope) {
            HStack(spacing: PUI.Spacing.md) {
                Text("Target")
                    .font(PUI.Typography.row)
                    .foregroundStyle(.primary)
                Spacer()
                Picker("Target", selection: bindingForRelationTier(def: def)) {
                    Text("Spaces").tag(1)
                    Text("Topics").tag(2)
                    Text("Projects").tag(3)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        } else {
            VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
                Text("Target ID")
                    .font(PUI.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                TextField("Type / Collection ID", text: bindingForRelationTargetID(def: def))
                    .textFieldStyle(.plain)
                    .font(PUI.Typography.row)
                    .onSubmit { /* binding setter handles commit */ }
                Text("Paste the target's ID. A searchable picker lands in a follow-up.")
                    .font(PUI.Typography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func relationMirrorRow(def: PropertyDefinition) -> some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
            Text("Mirror name")
                .font(PUI.Typography.sectionHeader)
                .foregroundStyle(.secondary)
            TextField("Reverse property name on target", text: bindingForRelationMirrorName(def: def))
                .textFieldStyle(.plain)
                .font(PUI.Typography.row)
            Text("Display name for the mirror property created on the target Type. Pairing lands in a follow-up.")
                .font(PUI.Typography.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func relationAllowsMultipleRow(def: PropertyDefinition) -> some View {
        HStack(spacing: PUI.Spacing.md) {
            Text("Allow multiple")
                .font(PUI.Typography.row)
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: bindingForRelationAllowsMultiple(def: def))
                .labelsHidden()
        }
    }

    private func isContextTierScope(_ scope: PropertyDefinition.RelationScope?) -> Bool {
        if case .some(.contextTier) = scope { return true }
        return false
    }

    /// UI-side projection of the 5-case scope discriminator.
    private enum RelationScopeKind: Hashable {
        case pageType, itemType, pageCollection, itemCollection, contextTier
    }

    private func scopeKind(of scope: PropertyDefinition.RelationScope?) -> RelationScopeKind? {
        switch scope {
        case .pageType: return .pageType
        case .itemType: return .itemType
        case .pageCollection: return .pageCollection
        case .itemCollection: return .itemCollection
        case .contextTier: return .contextTier
        case .none: return nil
        }
    }

    /// Construct a default RelationScope for a given kind. Container kinds
    /// start with an empty target ID; contextTier starts at tier 1.
    private func defaultScope(for kind: RelationScopeKind) -> PropertyDefinition.RelationScope {
        switch kind {
        case .pageType: return .pageType("")
        case .itemType: return .itemType("")
        case .pageCollection: return .pageCollection("")
        case .itemCollection: return .itemCollection("")
        case .contextTier: return .contextTier(1)
        }
    }

    private func targetID(of scope: PropertyDefinition.RelationScope?) -> String {
        switch scope {
        case .pageType(let id), .itemType(let id),
             .pageCollection(let id), .itemCollection(let id):
            return id
        default:
            return ""
        }
    }

    private func tier(of scope: PropertyDefinition.RelationScope?) -> Int {
        if case .contextTier(let t) = scope { return t }
        return 1
    }

    /// Build a new RelationScope keeping the current kind but replacing the
    /// target. No-op if kind is `.contextTier` (use tier-binding instead).
    private func withTargetID(_ id: String, kind: RelationScopeKind) -> PropertyDefinition.RelationScope {
        switch kind {
        case .pageType: return .pageType(id)
        case .itemType: return .itemType(id)
        case .pageCollection: return .pageCollection(id)
        case .itemCollection: return .itemCollection(id)
        case .contextTier: return .contextTier(1)
        }
    }

    // MARK: - Relation bindings

    private func bindingForRelationKind(def: PropertyDefinition) -> Binding<RelationScopeKind?> {
        Binding(
            get: { scopeKind(of: def.relationScope) },
            set: { newKind in
                Task {
                    await applyTransform { transformee in
                        if let k = newKind {
                            transformee.relationScope = defaultScope(for: k)
                        } else {
                            transformee.relationScope = nil
                        }
                    }
                }
            }
        )
    }

    private func bindingForRelationTargetID(def: PropertyDefinition) -> Binding<String> {
        Binding(
            get: { targetID(of: def.relationScope) },
            set: { newID in
                Task {
                    await applyTransform { transformee in
                        guard let kind = scopeKind(of: transformee.relationScope) else { return }
                        transformee.relationScope = withTargetID(newID, kind: kind)
                    }
                }
            }
        )
    }

    private func bindingForRelationTier(def: PropertyDefinition) -> Binding<Int> {
        Binding(
            get: { tier(of: def.relationScope) },
            set: { newTier in
                Task {
                    await applyTransform { transformee in
                        transformee.relationScope = .contextTier(newTier)
                    }
                }
            }
        )
    }

    private func bindingForRelationMirrorName(def: PropertyDefinition) -> Binding<String> {
        Binding(
            get: { def.dualProperty?.syncedPropertyID ?? "" },
            set: { newName in
                Task {
                    await applyTransform { transformee in
                        if newName.trimmingCharacters(in: .whitespaces).isEmpty {
                            transformee.dualProperty = nil
                        } else {
                            transformee.dualProperty = PropertyDefinition.DualPropertyConfig(
                                syncedPropertyID: newName,
                                syncedPropertyDefinedOnTypeID:
                                    transformee.dualProperty?.syncedPropertyDefinedOnTypeID ?? ""
                            )
                        }
                    }
                }
            }
        )
    }

    private func bindingForRelationAllowsMultiple(def: PropertyDefinition) -> Binding<Bool> {
        Binding(
            get: { def.allowsMultiple ?? false },
            set: { newValue in
                Task {
                    await applyTransform { transformee in
                        transformee.allowsMultiple = newValue
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
        case .date, .datetime: dateFormatPicker(def: def)
        default: EmptyView()
        }
    }

    /// Labeled inline selector: section-header title (left) + a plain dropdown
    /// (right) — a `Menu` hosting an inline `Picker` (checkmark on the current
    /// value, NO chevron glyph on the trigger). Shared shape for Display As /
    /// number format / date format.
    @ViewBuilder
    private func menuSelectorRow<P: View>(
        _ title: String,
        value: String,
        @ViewBuilder picker: () -> P
    ) -> some View {
        HStack(spacing: PUI.Spacing.md) {
            Text(title)
                .font(PUI.Typography.sectionHeader)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                picker()
                    .pickerStyle(.inline)
            } label: {
                Text(value)
                    .font(PUI.Typography.row)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func displayAsPicker(def: PropertyDefinition) -> some View {
        menuSelectorRow("Display As", value: displayAsLabel(def.displayAs)) {
            Picker("Display As", selection: displayAsSelectionBinding(def: def)) {
                Text("Box").tag(DisplayVariant.box)
                Text("Select").tag(DisplayVariant.select)
                Text("Chip").tag(DisplayVariant.chip)
            }
        }
    }

    @ViewBuilder
    private func numberFormatPicker(def: PropertyDefinition) -> some View {
        menuSelectorRow("Format", value: (def.numberFormat ?? .decimal).rawValue.capitalized) {
            Picker("Format", selection: bindingForNumberFormat(def: def)) {
                ForEach(PropertyDefinition.NumberFormat.allCases, id: \.self) { fmt in
                    Text(fmt.rawValue.capitalized).tag(fmt)
                }
            }
        }
    }

    @ViewBuilder
    private func dateFormatPicker(def: PropertyDefinition) -> some View {
        menuSelectorRow("Display as", value: def.dateFormat.map(dateFormatLabel) ?? "Default") {
            Picker("Display as", selection: bindingForDateFormat(def: def)) {
                Text("Default").tag(DateFormat?.none)
                ForEach(DateFormat.allCases, id: \.self) { fmt in
                    Text(dateFormatLabel(fmt)).tag(DateFormat?.some(fmt))
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
        // Placement (horizontal + vertical) is owned by `bottomBlock`, which
        // pins this row to the popover bottom on the standard rail.
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
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    private func commitRename() async {
        guard let typeID = parentTypeID(), let side else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        // Skip empty + no-op renames so Enter / blur / disappear can all fire
        // without double-writing or clobbering with an unchanged value.
        guard !trimmed.isEmpty, trimmed != currentDefinition()?.name else { return }
        do {
            switch side {
            case .pages:
                try await pageTypeManager.renameProperty(id: propertyID, in: typeID, to: trimmed)
            case .items:
                try await itemTypeManager.renameProperty(id: propertyID, in: typeID, to: trimmed)
            }
            commitError = nil
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
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
            commitError = PropertyEditorErrorMessage.string(for: error)
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
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }
}
