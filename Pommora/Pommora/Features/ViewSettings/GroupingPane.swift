import SwiftUI

/// View Settings → Grouping — the full redesigned grouping pane backed by
/// `GroupingPaneModel`. Replaces the legacy `GroupPane` picker list.
///
/// Structure (rows are contextual to the selected property's type):
///   - **Grouping** — Toggle bound to `model.groupingEnabled`.
///   - **Group By** — when ON, inline-expand property picker; "None" when OFF.
///   - **Date By** — Date/Datetime properties only; disclosure → popover.
///   - **Order** — disclosure → popover with type-specific label subset.
///   - **Options** — Select + Status only; chip + drag-handle list, no Add.
///     Draggable only in Manual order mode. Hidden when zero options.
///   - **Hide empty groups** — Toggle bound to `model.grouping.hideEmptyGroups`.
///   - **Empty group** — Top / Bottom control; hidden while hideEmptyGroups is on.
///
/// Persistence path: `model.onSave` routes through
/// `PageTypeManager.updateView(_:in:transform:)` — the same path as SortPane /
/// FilterPane / the old GroupPane. The model is created once from `currentView()`
/// in `body` and stored in `@State`; subsequent manager re-renders that swap the
/// live view are observed by reading `pageTypeManager` inside `onSave`.
struct GroupingPane: View {
    let scope: ViewSettingsScope
    @Binding var path: [ViewSettingsRoute]

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(TierConfigManager.self) private var tierConfigManager
    @Environment(ActiveViewStore.self) private var activeViewStore

    @State private var model: GroupingPaneModel?
    @State private var commitError: String?
    @State private var pickerExpanded: Bool = false

    var body: some View {
        ViewSettingsPane {
            PaneHeader(path: $path)
        } content: {
            content
        } footer: {
            emptyGroupFooter
        }
        .navigationBarBackButtonHidden(true)
        .onAppear { buildModel() }
    }

    // MARK: - Footer

    /// Pinned footer: "Hide empty groups" toggle + "Empty group" placement row.
    /// Visible only when a property is actively grouped AND the type has a nil
    /// bucket (i.e. not Checkbox). Empty when grouping is off or not applicable.
    @ViewBuilder
    private var emptyGroupFooter: some View {
        if let model {
            let grouping = model.grouping
            let props = ViewSettingsProperties.groupable(
                scope: scope, manager: pageTypeManager, tierConfig: tierConfigManager.config)
            let activeDef = grouping.flatMap { g in props.first(where: { $0.id == g.propertyID }) }

            if let grouping, let def = activeDef, def.type != .checkbox, !pickerExpanded {
                VStack(spacing: 0) {
                    PaneDivider()

                    LabeledToggleRow(
                        label: "Hide empty groups",
                        isOn: Binding(
                            get: { grouping.hideEmptyGroups },
                            set: { hide in model.update { $0.hideEmptyGroups = hide } }
                        ),
                        secondary: true
                    )

                    if !grouping.hideEmptyGroups {
                        EmptyGroupRow(
                            placement: Binding(
                                get: { grouping.emptyPlacement },
                                set: { p in model.update { $0.emptyPlacement = p } }
                            ),
                            secondary: true
                        )
                    }
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let model {
            paneRows(model: model)
        } else {
            ContentUnavailableView(
                "No view configured",
                systemImage: "rectangle.and.text.magnifyingglass",
                description: Text("loadAll should have minted a default view; reopen the popover.")
            )
        }
    }

    @ViewBuilder
    private func paneRows(model: GroupingPaneModel) -> some View {
        let grouping = model.grouping
        let props = ViewSettingsProperties.groupable(
            scope: scope, manager: pageTypeManager, tierConfig: tierConfigManager.config)
        let activeDef = grouping.flatMap { g in props.first(where: { $0.id == g.propertyID }) }

        VStack(spacing: 0) {
            PaneDivider()

            LabeledToggleRow(
                label: "Grouping",
                isOn: Binding(
                    get: { model.groupingEnabled },
                    set: { newValue in
                        if newValue {
                            model.setGroupingEnabled(true)
                            if model.grouping == nil {
                                withAnimation(.easeInOut(duration: 0.2)) { pickerExpanded = true }
                            }
                        } else {
                            model.setGroupingEnabled(false)
                            withAnimation(.easeInOut(duration: 0.2)) { pickerExpanded = false }
                        }
                    }
                )
            )

            GroupByRow(
                isEnabled: model.groupingEnabled,
                selectedDef: activeDef,
                props: props,
                pickerExpanded: $pickerExpanded,
                onSelect: { id in
                    model.selectProperty(id)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        pickerExpanded = false
                    }
                }
            )

            // --- Contextual rows: the property-specific menu. Hidden while the
            // picker is open so re-clicking Group By returns to the property list.
            if let grouping, let def = activeDef, !pickerExpanded {

                // Date By — only for date/datetime types
                if def.type == .date || def.type == .datetime {
                    DateByRow(
                        granularity: Binding(
                            get: { grouping.dateGranularity ?? .day },
                            set: { gran in model.update { $0.dateGranularity = gran } }
                        )
                    )
                }

                // Order — type-specific label set
                OrderRow(
                    propertyType: def.type,
                    orderMode: Binding(
                        get: { grouping.orderMode },
                        set: { mode in model.update { $0.orderMode = mode } }
                    )
                )

                PaneDivider()

                // Options area — Select + Status only, only when options exist
                OptionsSection(def: def, grouping: grouping, model: model)
            }

            if let err = commitError {
                Text(err)
                    .font(PUI.Typography.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, PUI.Row.paddingHorizontal)
                    .padding(.vertical, PUI.Row.paddingVertical)
            }
        }
    }

    // MARK: - Model initialization

    private func buildModel() {
        guard let view = currentView(), let cid = containerID() else { return }
        let viewID = view.id
        model = GroupingPaneModel(config: view.group ?? .structural) { [self] newConfig in
            Task {
                do {
                    try await pageTypeManager.updateView(viewID, in: cid) { v in
                        v.group = newConfig
                    }
                    commitError = nil
                } catch {
                    commitError = PropertyEditorErrorMessage.string(for: error)
                }
            }
        }
    }

    private func currentView() -> SavedView? {
        activeViewStore.resolvedActiveView(for: scope, manager: pageTypeManager)
    }

    private func containerID() -> String? { scope.containerID }
}

// MARK: - GroupByRow

/// Inline-expand property picker. Tapping the row reveals the
/// `ViewSettingsProperties.groupable` list (schema order, checkmark on active);
/// picking collapses the list and fires `onSelect`. Chevron is only shown when a
/// property is selected; "None" is only shown when enabled but no property chosen.
private struct GroupByRow: View {
    let isEnabled: Bool
    let selectedDef: PropertyDefinition?
    let props: [PropertyDefinition]
    @Binding var pickerExpanded: Bool
    let onSelect: (String) -> Void

    /// Trailing value label: property name when one is selected; "None" when
    /// enabled but nothing chosen; empty string when grouping is disabled.
    private var valueLabel: String {
        if let def = selectedDef { return def.name }
        return isEnabled ? "None" : ""
    }

    /// Chevron only appears when a property is actively selected.
    private var showChevron: Bool { selectedDef != nil }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                guard isEnabled else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    pickerExpanded.toggle()
                }
            } label: {
                HStack(spacing: PUI.Row.interSpacing) {
                    Text("Group By")
                        .font(PUI.Typography.row)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    if !valueLabel.isEmpty {
                        Text(valueLabel)
                            .font(PUI.Typography.row)
                            .foregroundStyle(.secondary)
                    }
                    if showChevron {
                        DisclosureChevron(isExpanded: pickerExpanded)
                    }
                }
                .padding(.horizontal, PUI.Row.paddingHorizontal)
                .padding(.vertical, PUI.Row.paddingVertical)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if pickerExpanded {
                VStack(spacing: 0) {
                    ForEach(props, id: \.id) { def in
                        SelectableOptionRow(
                            label: def.name, icon: def.displayIcon,
                            isSelected: selectedDef?.id == def.id
                        ) {
                            onSelect(def.id)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - DateByRow

/// Disclosure row → popover of `DateGranularity` values. Only surfaces for
/// Date / Datetime property types.
private struct DateByRow: View {
    @Binding var granularity: DateGranularity
    @State private var popoverOpen: Bool = false

    var body: some View {
        HStack(spacing: PUI.Row.interSpacing) {
            Text("Date By")
                .font(PUI.Typography.row)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button {
                popoverOpen = true
            } label: {
                HStack(spacing: PUI.Row.interSpacing) {
                    Text(granularity.displayLabel)
                        .font(PUI.Typography.row)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(PUI.Icon.chevron)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $popoverOpen, arrowEdge: .bottom) {
                DateGranularityPicker(selected: $granularity)
            }
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)
        .contentShape(Rectangle())
    }
}

private struct DateGranularityPicker: View {
    @Binding var selected: DateGranularity

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(DateGranularity.allCases, id: \.self) { gran in
                SelectableOptionRow(
                    label: gran.displayLabel,
                    isSelected: selected == gran,
                    onSelect: { selected = gran }
                )
            }
        }
        .padding(.vertical, PUI.Spacing.xs)
        .fixedSize(horizontal: true, vertical: true)
    }
}

// MARK: - OrderRow

/// Disclosure row → popover. The label subset is type-specific:
///   - Select: Default (.configured) / Manual (.manual)
///   - Status: Ascending (.configured) / Descending (.reversed) / Manual (.manual)
///   - Date: Ascending (.configured) / Descending (.reversed)
///   - Checkbox: Off (.configured) / On (.reversed)
private struct OrderRow: View {
    let propertyType: PropertyType
    @Binding var orderMode: GroupOrderMode
    @State private var popoverOpen: Bool = false

    var body: some View {
        HStack(spacing: PUI.Row.interSpacing) {
            Text("Order")
                .font(PUI.Typography.row)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button {
                popoverOpen = true
            } label: {
                HStack(spacing: PUI.Row.interSpacing) {
                    Text(orderLabel(for: orderMode, type: propertyType))
                        .font(PUI.Typography.row)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(PUI.Icon.chevron)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $popoverOpen, arrowEdge: .bottom) {
                OrderModePicker(propertyType: propertyType, selected: $orderMode)
            }
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)
        .contentShape(Rectangle())
    }

    private func orderLabel(for mode: GroupOrderMode, type: PropertyType) -> String {
        GroupOrderOptions.label(for: mode, type: type)
    }
}

/// The per-type Order-popout options — the single source for both the picker rows
/// and the Order row's trailing label, so the two can never drift. A mode the type
/// doesn't expose (e.g. Select has no `.reversed`) falls back to the type's first
/// option's label, preserving the prior defensive mapping.
private enum GroupOrderOptions {
    static func entries(for type: PropertyType) -> [(mode: GroupOrderMode, label: String)] {
        switch type {
        case .select: return [(.configured, "Default"), (.manual, "Manual")]
        case .status: return [(.configured, "Ascending"), (.reversed, "Descending"), (.manual, "Manual")]
        case .date, .datetime: return [(.configured, "Ascending"), (.reversed, "Descending")]
        case .checkbox: return [(.configured, "Off"), (.reversed, "On")]
        default: return []
        }
    }

    static func label(for mode: GroupOrderMode, type: PropertyType) -> String {
        let options = entries(for: type)
        return options.first(where: { $0.mode == mode })?.label
            ?? options.first?.label
            ?? mode.displayLabel
    }
}

private struct OrderModePicker: View {
    let propertyType: PropertyType
    @Binding var selected: GroupOrderMode

    private struct ModeEntry: Identifiable {
        let id: String
        let mode: GroupOrderMode
        let label: String
    }

    private var entries: [ModeEntry] {
        GroupOrderOptions.entries(for: propertyType).map {
            ModeEntry(id: $0.mode.rawValue, mode: $0.mode, label: $0.label)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                SelectableOptionRow(
                    label: entry.label,
                    isSelected: selected == entry.mode,
                    onSelect: { selected = entry.mode }
                )
            }
        }
        .padding(.vertical, PUI.Spacing.xs)
        .fixedSize(horizontal: true, vertical: true)
    }
}

// MARK: - OptionsSection

/// Chip + drag-handle option list for Select / Status properties.
/// Not shown for other groupable types, or when the property has zero options.
/// Delegates to `GroupingOptionsList`.
private struct OptionsSection: View {
    let def: PropertyDefinition
    let grouping: PropertyGrouping
    let model: GroupingPaneModel

    private var selectOptions: [PropertyDefinition.SelectOption] { def.selectOptions ?? [] }
    private var statusGroups: [PropertyDefinition.StatusGroup] { def.statusGroups ?? [] }

    var body: some View {
        switch def.type {
        case .select:
            selectSection
        case .status:
            statusSection
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var selectSection: some View {
        let opts = selectOptions
        if !opts.isEmpty {
            VStack(spacing: 0) {
                PaneDivider()
                GroupingOptionsList(
                    chips: orderedSelectChips(opts),
                    isDraggable: grouping.orderMode == .manual,
                    onReorder: { newOrder in
                        model.update { $0.order = newOrder }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        let groups = statusGroups
        let allOpts = groups.flatMap(\.options)
        if !allOpts.isEmpty {
            VStack(spacing: 0) {
                PaneDivider()
                switch grouping.orderMode {
                case .manual:
                    GroupingOptionsList(
                        chips: orderedStatusChips(groups),
                        isDraggable: true,
                        onReorder: { newOrder in
                            model.update { $0.order = newOrder }
                        }
                    )
                case .reversed:
                    // Flat reversed chip list — mirrors what the view renders.
                    GroupingOptionsList(
                        chips: flatStatusChips(groups).reversed(),
                        isDraggable: false,
                        onReorder: { _ in }
                    )
                case .configured:
                    GroupingStatusGroupedPreview(groups: groups)
                }
            }
        }
    }

    /// Chips ordered by active `orderMode`:
    /// `.configured` → schema order; `.reversed` → schema reversed;
    /// `.manual` → `grouping.order` first, remaining in schema order.
    private func orderedSelectChips(
        _ opts: [PropertyDefinition.SelectOption]
    ) -> [PropertyChipOption] {
        let chips = opts.map { $0.asChipOption() }
        switch grouping.orderMode {
        case .reversed:
            return chips.reversed()
        case .manual:
            guard let order = grouping.order else { return chips }
            var result: [PropertyChipOption] = []
            for id in order {
                if let chip = chips.first(where: { $0.id == id }) {
                    result.append(chip)
                }
            }
            for chip in chips where !result.contains(where: { $0.id == chip.id }) {
                result.append(chip)
            }
            return result
        case .configured:
            return chips
        }
    }

    /// Flat status options for manual-mode drag list.
    /// `grouping.order` first, remaining appended in schema order.
    private func orderedStatusChips(
        _ groups: [PropertyDefinition.StatusGroup]
    ) -> [PropertyChipOption] {
        let allChips = flatStatusChips(groups)
        guard let order = grouping.order else { return allChips }
        var result: [PropertyChipOption] = []
        for id in order {
            if let chip = allChips.first(where: { $0.id == id }) {
                result.append(chip)
            }
        }
        for chip in allChips where !result.contains(where: { $0.id == chip.id }) {
            result.append(chip)
        }
        return result
    }

    /// Flat schema-ordered chips for `.configured` and `.reversed` non-manual previews.
    private func flatStatusChips(
        _ groups: [PropertyDefinition.StatusGroup]
    ) -> [PropertyChipOption] {
        groups.flatMap { group in
            group.options.map { opt in
                opt.asChipOption(groupColor: group.color)
            }
        }
    }
}

/// Non-draggable preview of Status options nested under 3 fixed group labels.
private struct GroupingStatusGroupedPreview: View {
    let groups: [PropertyDefinition.StatusGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xl) {
            ForEach(groups, id: \.id) { group in
                if !group.options.isEmpty {
                    VStack(alignment: .leading, spacing: PUI.Spacing.sm) {
                        Text(group.label)
                            .font(PUI.Typography.sectionHeader)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, PUI.Row.paddingHorizontal)
                        ForEach(group.options, id: \.id) { opt in
                            StatusPreviewRow(
                                option: opt,
                                groupColor: group.color
                            )
                        }
                    }
                }
            }
        }
        .padding(.vertical, PUI.Spacing.md)
    }
}

/// A non-draggable chip row for the status grouped preview.
private struct StatusPreviewRow: View {
    let option: PropertyDefinition.StatusOption
    let groupColor: PropertyDefinition.SelectColor

    var body: some View {
        HStack(spacing: PUI.Row.interSpacing) {
            PropertyChip(
                label: option.label,
                color: PropertyChipColor(selectColor: option.color ?? groupColor)
            )
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .font(PUI.Typography.chip)
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
    }
}

// MARK: - EmptyGroupRow

/// Top / Bottom selection for empty group placement.
private struct EmptyGroupRow: View {
    @Binding var placement: EmptyPlacement
    var secondary: Bool = false
    @State private var popoverOpen: Bool = false

    var body: some View {
        HStack(spacing: PUI.Row.interSpacing) {
            Text("Empty group")
                .font(secondary ? .subheadline : PUI.Typography.row)
                .foregroundStyle(secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            Spacer(minLength: 0)
            Button {
                popoverOpen = true
            } label: {
                HStack(spacing: PUI.Row.interSpacing) {
                    Text(placement.displayLabel)
                        .font(PUI.Typography.row)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(PUI.Icon.chevron)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $popoverOpen, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach([EmptyPlacement.top, EmptyPlacement.bottom], id: \.self) { p in
                        SelectableOptionRow(
                            label: p.displayLabel,
                            isSelected: placement == p,
                            onSelect: { placement = p }
                        )
                    }
                }
                .padding(.vertical, PUI.Spacing.xs)
                .fixedSize(horizontal: true, vertical: true)
            }
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, secondary ? PUI.Spacing.xs : PUI.Row.paddingVertical)
        .contentShape(Rectangle())
    }
}

// MARK: - Display label extensions

extension DateGranularity {
    var displayLabel: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }
}

extension GroupOrderMode {
    var displayLabel: String {
        switch self {
        case .configured: return "Default"
        case .reversed: return "Reversed"
        case .manual: return "Manual"
        }
    }
}

extension EmptyPlacement {
    var displayLabel: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }
}
