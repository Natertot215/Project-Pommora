import SwiftUI

/// View Settings → Filter — edits the active SavedView's `FilterGroup`
/// (a `MatchMode` + a flat list of `FilterRule`s).
///
/// Each rule names a property, an operator (restricted to the ones
/// `FilterEvaluator` honors for that property's `PropertyType`), and an
/// optional serialized value. Presence operators (`is_empty` / `is_not_empty`)
/// carry no value. Every read + write resolves the active view by stable ID off
/// the live `PageTypeManager` (never the stale `ViewSettingsScope` snapshot),
/// then persists the WHOLE rewritten `FilterGroup` through
/// `PageTypeManager.updateView(_:in:transform:)` — mirrors `SortPane`.
///
/// The Cover sentinel never appears in the property list (filtered by
/// `ViewSettingsProperties.filterable`, shared with the Group pane).
struct FilterPane: View {
    let scope: ViewSettingsScope
    @Binding var path: [ViewSettingsRoute]

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(TierConfigManager.self) private var tierConfigManager
    @Environment(ActiveViewStore.self) private var activeViewStore

    @State private var commitError: String?

    var body: some View {
        ViewSettingsPane {
            PaneHeader(path: $path)
        } content: {
            content
        }
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if let view = currentView() {
            rows(for: view)
        } else {
            ContentUnavailableView(
                "No view configured",
                systemImage: "rectangle.and.text.magnifyingglass",
                description: Text("loadAll should have minted a default Table view; reopen the popover.")
            )
        }
    }

    @ViewBuilder
    private func rows(for view: SavedView) -> some View {
        let group = view.filter ?? FilterGroup(match: .all, rules: [])
        let props = ViewSettingsProperties.filterable(
            scope: scope, manager: pageTypeManager, tierConfig: tierConfigManager.config)
        VStack(spacing: 0) {
            matchSelector(group)
            PaneDivider()
            ForEach(Array(group.rules.enumerated()), id: \.offset) { index, rule in
                FilterRuleRow(
                    rule: rule,
                    properties: props,
                    onChange: { updated in Task { await replaceRule(at: index, with: updated, in: group) } },
                    onRemove: { Task { await removeRule(at: index, in: group) } }
                )
            }
            addRuleButton(props: props, group: group)
            if let err = commitError {
                Text(err)
                    .font(PUI.Typography.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, PUI.Row.paddingHorizontal)
                    .padding(.vertical, PUI.Row.paddingVertical)
            }
        }
    }

    @ViewBuilder
    private func matchSelector(_ group: FilterGroup) -> some View {
        LabeledMenuSelector(title: "Match", value: group.match == .all ? "All" : "Any") {
            Picker(
                "Match",
                selection: Binding(
                    get: { group.match },
                    set: { mode in Task { await setMatch(mode, in: group) } }
                )
            ) {
                Text("All").tag(MatchMode.all)
                Text("Any").tag(MatchMode.any)
            }
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)
    }

    @ViewBuilder
    private func addRuleButton(props: [PropertyDefinition], group: FilterGroup) -> some View {
        Button {
            guard let first = props.first else { return }
            let op = ViewSettingsProperties.operators(for: first.type).first ?? .isEqual
            Task { await appendRule(FilterRule(propertyID: first.id, op: op.rawValue, value: nil), in: group) }
        } label: {
            HStack(spacing: PUI.Row.interSpacing) {
                Image(systemName: "plus")
                    .font(PUI.Icon.plus)
                    .frame(width: PUI.Icon.leadingFrame)
                Text("Add filter")
                    .font(PUI.Typography.row)
                Spacer()
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, PUI.Row.paddingHorizontal)
            .padding(.vertical, PUI.Row.paddingVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(props.isEmpty)
    }

    // MARK: - Commit (whole-FilterGroup rewrites)

    private func setMatch(_ mode: MatchMode, in group: FilterGroup) async {
        var next = group
        next.match = mode
        await write(next)
    }

    private func appendRule(_ rule: FilterRule, in group: FilterGroup) async {
        var next = group
        next.rules.append(rule)
        await write(next)
    }

    private func replaceRule(at index: Int, with rule: FilterRule, in group: FilterGroup) async {
        guard group.rules.indices.contains(index) else { return }
        var next = group
        next.rules[index] = rule
        await write(next)
    }

    private func removeRule(at index: Int, in group: FilterGroup) async {
        guard group.rules.indices.contains(index) else { return }
        var next = group
        next.rules.remove(at: index)
        await write(next)
    }

    /// Writes the whole `FilterGroup` (clearing `filter` when empty so an
    /// emptied filter reads as "no filter" rather than an identity group).
    private func write(_ group: FilterGroup) async {
        guard let view = currentView(), let cid = containerID() else { return }
        let viewID = view.id
        do {
            try await pageTypeManager.updateView(viewID, in: cid) { v in
                v.filter = group.rules.isEmpty && group.match == .all ? nil : group
            }
            commitError = nil
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    // MARK: - Lookups (re-query live off the manager by stable ID)

    /// Resolves the ACTIVE view via the shared resolver, so the pane edits
    /// whichever view the user is currently viewing rather than the container's
    /// first view.
    private func currentView() -> SavedView? {
        guard let cid = containerID() else { return nil }
        return activeViewStore.resolvedActiveView(in: cid, manager: pageTypeManager)
    }

    private func containerID() -> String? {
        switch scope {
        case .pageType(let t): return t.id
        case .pageCollection(let c): return c.id
        default: return nil
        }
    }
}

// MARK: - Shared property catalog (Filter + Group)

/// The property lists the Filter and Group panes offer, plus the per-type
/// operator matrix the Filter pane builds. DRY — both panes resolve their
/// candidate properties here so the Cover-exclusion + tier handling lives once.
enum ViewSettingsProperties {
    /// Filterable properties: every schema property (Cover excluded) + the three
    /// tier relations + the reserved Recent (modified) date. `FilterEvaluator`
    /// honors tier rules and date rules, so both are offered.
    ///
    /// A USER property typed `.lastEditedTime` is excluded — that case carries no
    /// readable stored value, so its date operators can't be satisfied (pass-all
    /// no-op). The reserved Recent column is exempt: it's the special-cased
    /// `_modified_at` ID, the one entry that actually resolves a modified Date.
    static func filterable(
        scope: ViewSettingsScope,
        manager: PageTypeManager,
        tierConfig: TierConfig
    ) -> [PropertyDefinition] {
        schema(scope: scope, manager: manager, tierConfig: tierConfig).filter { def in
            guard def.id != ReservedPropertyID.cover else { return false }
            return def.type != .lastEditedTime || def.id == ReservedPropertyID.modifiedAt
        }
    }

    /// Groupable properties: only the bucketable single-value types the
    /// `GroupResolver` can key on — Select / Status / Checkbox. Tiers (multi-id
    /// relations) and Cover are never groupable.
    static func groupable(
        scope: ViewSettingsScope,
        manager: PageTypeManager,
        tierConfig: TierConfig
    ) -> [PropertyDefinition] {
        schema(scope: scope, manager: manager, tierConfig: tierConfig).filter { def in
            def.id != ReservedPropertyID.cover && isGroupable(def.type)
        }
    }

    /// Operators `FilterEvaluator` actually honors for a given type — the pane
    /// offers only these so a rule never picks a no-op operator. Condensed
    /// exhaustive switch over `PropertyType` (HARD RULE).
    static func operators(for type: PropertyType) -> [FilterOperator] {
        switch type {
        case .number:
            return [.greaterThan, .lessThan, .isEqual, .isEmpty]
        case .date, .datetime, .lastEditedTime:
            return [.onOrAfter, .onOrBefore, .isEmpty]
        case .select, .status, .url:
            return [.isEqual, .isNot, .isEmpty]
        case .multiSelect:
            return [.isEqual, .isNot, .isEmpty]
        case .checkbox:
            return [.isEqual]
        case .relation:
            // Tier relations: membership + presence (the list matrix).
            return [.isEqual, .isNot, .isEmpty]
        case .file:
            return [.isEmpty, .isNotEmpty]
        }
    }

    /// Human label for an operator in the rule-row menu.
    static func label(for op: FilterOperator) -> String {
        switch op {
        case .isEqual: return "is"
        case .isNot: return "is not"
        case .contains: return "contains"
        case .doesNotContain: return "does not contain"
        case .isEmpty: return "is empty"
        case .isNotEmpty: return "is not empty"
        case .greaterThan: return "greater than"
        case .lessThan: return "less than"
        case .onOrAfter: return "on or after"
        case .onOrBefore: return "on or before"
        }
    }

    /// Whether an operator needs a value editor (presence ops do not).
    static func needsValue(_ op: FilterOperator) -> Bool {
        switch op {
        case .isEmpty, .isNotEmpty: return false
        default: return true
        }
    }

    // MARK: - Internals

    static func isGroupable(_ type: PropertyType) -> Bool {
        switch type {
        case .select, .status, .checkbox, .date, .datetime: return true
        default: return false
        }
    }

    /// Schema (user properties + tiers) for the scope's parent type, plus the
    /// reserved Recent (modified) date as a synthetic filterable entry.
    private static func schema(
        scope: ViewSettingsScope,
        manager: PageTypeManager,
        tierConfig: TierConfig
    ) -> [PropertyDefinition] {
        guard let typeID = parentTypeID(scope) else { return [] }
        let resolved =
            manager.types.first(where: { $0.id == typeID })?
            .resolvedProperties(tierConfig: tierConfig) ?? []
        let recent = PropertyDefinition(
            id: ReservedPropertyID.modifiedAt, name: "Last edited", type: .lastEditedTime,
            icon: "clock.arrow.circlepath")
        return resolved + [recent]
    }

    private static func parentTypeID(_ scope: ViewSettingsScope) -> String? {
        switch scope {
        case .pageType(let t): return t.id
        case .pageCollection(let c): return c.typeID
        default: return nil
        }
    }
}

// MARK: - FilterRuleRow

/// One filter rule: property menu → operator menu (type-filtered) → value
/// editor (text / number / date / option / checkbox; absent for presence ops).
/// Isolated as a plain-value sub-view (quirk 12 — keeps GRDB's `String`
/// overload pollution out of the parent `@ViewBuilder`).
private struct FilterRuleRow: View {
    let rule: FilterRule
    let properties: [PropertyDefinition]
    let onChange: (FilterRule) -> Void
    let onRemove: () -> Void

    private var def: PropertyDefinition? {
        properties.first(where: { $0.id == rule.propertyID })
    }

    private var op: FilterOperator { FilterOperator(rawValue: rule.op) ?? .isEqual }

    var body: some View {
        VStack(spacing: PUI.Spacing.sm) {
            HStack(spacing: PUI.Spacing.sm) {
                propertyMenu
                operatorMenu
                Spacer(minLength: 0)
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                        .font(PUI.Icon.visibility)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove filter")
            }
            if ViewSettingsProperties.needsValue(op) {
                valueEditor
            }
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)
    }

    @ViewBuilder
    private var propertyMenu: some View {
        Menu {
            Picker(
                "Property",
                selection: Binding(
                    get: { rule.propertyID },
                    set: { newID in onChange(ruleForNewProperty(newID)) }
                )
            ) {
                ForEach(properties, id: \.id) { p in
                    Text(p.name).tag(p.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(def?.name ?? "Property")
                .font(PUI.Typography.row)
                .foregroundStyle(.primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var operatorMenu: some View {
        let ops = ViewSettingsProperties.operators(for: def?.type ?? .url)
        Menu {
            Picker(
                "Operator",
                selection: Binding(
                    get: { op },
                    set: { newOp in onChange(ruleForNewOperator(newOp)) }
                )
            ) {
                ForEach(ops, id: \.self) { o in
                    Text(ViewSettingsProperties.label(for: o)).tag(o)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(ViewSettingsProperties.label(for: op))
                .font(PUI.Typography.row)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch def?.type {
        case .number:
            numberField
        case .date, .datetime, .lastEditedTime:
            dateField
        case .checkbox:
            checkboxField
        case .select, .status:
            optionMenu
        default:
            textField
        }
    }

    private var textField: some View {
        TextField(
            "Value",
            text: Binding(
                get: { rule.value ?? "" },
                set: { onChange(ruleWithValue($0.isEmpty ? nil : $0)) }
            )
        )
        .textFieldStyle(.roundedBorder)
        .font(PUI.Typography.row)
    }

    private var numberField: some View {
        TextField(
            "Number",
            text: Binding(
                get: { rule.value ?? "" },
                set: { onChange(ruleWithValue($0.isEmpty ? nil : $0)) }
            )
        )
        .textFieldStyle(.roundedBorder)
        .font(PUI.Typography.row)
    }

    private var dateField: some View {
        DatePicker(
            "",
            selection: Binding(
                get: { Self.parseDate(rule.value) ?? Date() },
                set: { onChange(ruleWithValue(Self.formatDate($0))) }
            ),
            displayedComponents: .date
        )
        .labelsHidden()
        .datePickerStyle(.compact)
    }

    private var checkboxField: some View {
        Toggle(
            "Checked",
            isOn: Binding(
                get: { rule.value == "true" },
                set: { onChange(ruleWithValue($0 ? "true" : "false")) }
            )
        )
        .toggleStyle(.checkbox)
        .font(PUI.Typography.row)
    }

    @ViewBuilder
    private var optionMenu: some View {
        let options = Self.options(for: def)
        Menu {
            Picker(
                "Value",
                selection: Binding(
                    get: { rule.value ?? "" },
                    set: { onChange(ruleWithValue($0.isEmpty ? nil : $0)) }
                )
            ) {
                ForEach(options, id: \.value) { opt in
                    Text(opt.label).tag(opt.value)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(Self.optionLabel(rule.value, in: options) ?? "Select…")
                .font(PUI.Typography.row)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Rule rebuilders

    /// Switching the property resets the operator to that type's first valid op
    /// and drops a stale value.
    private func ruleForNewProperty(_ newID: String) -> FilterRule {
        let newType = properties.first(where: { $0.id == newID })?.type ?? .url
        let newOp = ViewSettingsProperties.operators(for: newType).first ?? .isEqual
        return FilterRule(propertyID: newID, op: newOp.rawValue, value: nil)
    }

    /// Switching the operator preserves the property; drops the value when the
    /// new operator needs none.
    private func ruleForNewOperator(_ newOp: FilterOperator) -> FilterRule {
        let keepValue = ViewSettingsProperties.needsValue(newOp) ? rule.value : nil
        return FilterRule(propertyID: rule.propertyID, op: newOp.rawValue, value: keepValue)
    }

    private func ruleWithValue(_ value: String?) -> FilterRule {
        FilterRule(propertyID: rule.propertyID, op: rule.op, value: value)
    }

    // MARK: - Option helpers (plain values — quirk 12)

    private struct Option {
        let value: String
        let label: String
    }

    private static func options(for def: PropertyDefinition?) -> [Option] {
        guard let def else { return [] }
        if let opts = def.selectOptions {
            return opts.map { Option(value: $0.value, label: $0.label) }
        }
        if let groups = def.statusGroups {
            return groups.flatMap { $0.options.map { Option(value: $0.value, label: $0.label) } }
        }
        return []
    }

    private static func optionLabel(_ value: String?, in options: [Option]) -> String? {
        guard let value else { return nil }
        return options.first(where: { $0.value == value })?.label
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        return df.date(from: s)
    }

    private static func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        return df.string(from: date)
    }
}
