import SwiftUI

struct PropertyEditorRow: View {
    let definition: PropertyDefinition
    @Binding var value: PropertyValue
    /// Supplied by hosts that can edit context-links inline (defaulted so non-relation
    /// call sites compile unchanged). `index` feeds the picker's candidate query;
    /// `relationDisplay` renders the current value as icon+title chips.
    var index: PommoraIndex? = nil
    var relationDisplay: ContextDisplayResolver? = nil

    @State private var dateEditorOpen = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(definition.name)
                .frame(width: 100, alignment: .leading)
                .foregroundStyle(.secondary)
            editor
            Spacer()
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch definition.type {
        case .number:
            numberEditor
        case .checkbox:
            checkboxEditor
        case .date, .datetime:
            dateEditor
        case .select:
            selectEditor
        case .multiSelect:
            multiSelectEditor
        case .relation:
            relationEditor
        case .url:
            urlEditor
        case .status:
            statusEditor
        case .lastEditedTime:
            lastEditedTimeEditor
        case .file:
            fileEditor
        }
    }

    // MARK: - Editors

    private var numberEditor: some View {
        TextField(
            "",
            value: Binding(
                get: { if case .number(let n) = value { return n } else { return 0.0 } },
                set: { value = .number($0) }
            ), format: .number
        )
        .textFieldStyle(.roundedBorder)
        .frame(width: 120)
    }

    private var checkboxEditor: some View {
        Toggle(
            "",
            isOn: Binding(
                get: { if case .checkbox(let b) = value { return b } else { return false } },
                set: { value = .checkbox($0) }
            )
        )
        .labelsHidden()
    }

    /// Unified Date editor. Inspector rows stay compact: the formatted value
    /// is a tappable field pill that opens Pommora's custom `DateTimePicker`
    /// (glass calendar + bespoke time row) in a popover — the picker draws its
    /// own panel, so it's presented chromeless. Time inclusion comes from the
    /// property's `timeFormat`; single-date mode maps `Date` ⇄
    /// `DateSelection.single`.
    private var dateEditor: some View {
        Button {
            dateEditorOpen = true
        } label: {
            Text(dateDisplayString)
                .font(PUI.Typography.row)
                .foregroundStyle(hasDateValue ? .primary : .secondary)
                .padding(.horizontal, PUI.Spacing.md)
                .padding(.vertical, PUI.Spacing.xs)
                .fieldBackground()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $dateEditorOpen, arrowEdge: .bottom) {
            DateTimePicker(
                selection: dateSelectionBinding,
                isTimeSet: isTimeSetBinding,
                mode: .single,
                timeFormat: definition.timeFormat ?? .none
            )
            .presentationBackground(.clear)
        }
    }

    private var hasDateValue: Bool { value.dateSelection != nil }

    /// Formatted via the canonical `DateFormat` / `TimeFormat` renderers.
    /// Time is only appended when the stored value is `.datetime` — a `.date`
    /// value means the user never set a time, so it renders date-only even on
    /// a datetime property.
    private var dateDisplayString: String {
        guard let date = value.dateSelection?.anchorDate else { return "Empty" }
        let dateStr = (definition.dateFormat ?? .full).string(from: date)
        guard case .datetime = value,
            let time = (definition.timeFormat ?? .none).string(from: date)
        else { return dateStr }
        return "\(dateStr) \(time)"
    }

    private var dateSelectionBinding: Binding<DateSelection?> {
        let timeFormat = definition.timeFormat ?? .none
        return Binding(
            get: { value.dateSelection },
            set: { newSel in
                let hasTime: Bool
                if case .datetime = value { hasTime = true } else { hasTime = false }
                value = .from(dateSelection: newSel, timeFormat: timeFormat, isTimeSet: hasTime)
            }
        )
    }

    private var isTimeSetBinding: Binding<Bool> {
        Binding(
            get: {
                if case .datetime = value { return true }
                return false
            },
            set: { newIsTimeSet in
                guard let date = value.dateSelection?.anchorDate else { return }
                let tf = definition.timeFormat ?? .none
                guard tf.showsTime else { return }
                value = .from(dateSelection: .single(date), timeFormat: tf, isTimeSet: newIsTimeSet)
            }
        )
    }

    private var selectEditor: some View {
        let options = definition.selectOptions ?? []
        return Picker(
            "",
            selection: Binding(
                get: { if case .select(let s) = value { return s } else { return "" } },
                set: { value = .select($0) }
            )
        ) {
            Text("—").tag("")
            ForEach(options) { opt in
                Text(opt.label).tag(opt.value)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 220)
    }

    private var multiSelectEditor: some View {
        let options = (definition.selectOptions ?? []).map(\.value)
        return MultiSelectChips(
            options: options,
            selected: Binding(
                get: { if case .multiSelect(let xs) = value { return xs } else { return [] } },
                set: { value = .multiSelect($0) }
            ),
            allowsAddingOptions: false  // schema edit is its own concern
        )
    }

    @ViewBuilder
    private var relationEditor: some View {
        if let target = definition.relationTarget {
            ContextValueEditor(
                ids: Binding(
                    get: { if case .relation(let ids) = value { return ids } else { return [] } },
                    set: { value = .relation($0) }
                ),
                scope: target,
                index: index,
                resolver: relationDisplay
            )
        } else {
            Text("Relation has no target")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusEditor: some View {
        let groups = definition.statusGroups ?? []
        let opts: [PropertyChipOption] = groups.flatMap { g in
            g.options.map { $0.asChipOption(groupColor: g.color) }
        }
        let current: String? = {
            if case .status(let v) = value { return v }
            return nil
        }()
        return ChipDropdown(
            options: .constant(opts),
            selectionMode: .single,
            selectedIDs: current.map { Set([$0]) } ?? [],
            onPick: { value = .status($0.id) },
            size: .compact
        )
    }

    private var lastEditedTimeEditor: some View {
        let formatted: String = {
            if case .lastEditedTime = value {
                return DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
            }
            return "—"
        }()
        return Text(formatted)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var fileEditor: some View {
        let count: Int = {
            if case .file(let refs) = value { return refs.count }
            return 0
        }()
        return Text("\(count) file(s)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var urlEditor: some View {
        TextField(
            "https://…",
            text: Binding(
                get: { if case .url(let u) = value { return u.absoluteString } else { return "" } },
                set: { newText in
                    if let url = URL(string: newText), url.scheme != nil {
                        value = .url(url)
                    }
                }
            )
        )
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 320)
    }
}
