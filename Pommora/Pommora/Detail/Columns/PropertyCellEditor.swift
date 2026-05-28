import SwiftUI

/// Cell wrapper that owns a click-to-edit popover anchor and dispatches to
/// a type-appropriate editor view. Tap the cell → popover opens anchored
/// to the cell → user edits the value → outside-click / ESC dismisses + the
/// passed-in `commit` closure persists the draft via the relevant content
/// manager (PageContentManager.updatePageProperty / ItemContentManager.
/// updateItemProperty from Tasks 13+14).
///
/// LastEditedTime cells render as plain PropertyCellDisplay with no tap
/// gesture (read-only by design).
///
/// Per-type editor map (locked):
///   - number → bound TextField (Double parser)
///   - checkbox → toggle the cell's bool value on tap (no popover; the
///     display IS the affordance)
///   - date / datetime → DatePicker (graphical for date, graphical + time
///     for datetime)
///   - select → ChipDropdown (.single) — pulled from the Component Library
///   - multiSelect → ChipDropdown (.multi) — checkboxes + drag-reorder
///   - status → ChipDropdown (.single), options flattened across groups
///   - url → TextField with `keyboardType` URL hint
///   - relation → placeholder note ("v0.3.1.x") + RelationPicker wiring
///     deferred until index resolver flows through to the cell
///   - file → FileAttachmentEditor (existing component)
///   - lastEditedTime → read-only display, no popover
struct PropertyCellEditor: View {
    let definition: PropertyDefinition
    let value: PropertyValue?
    let relationResolver: (String) -> (icon: String, title: String)?
    let commit: (PropertyValue?) -> Void

    @State private var isPresented: Bool = false
    @State private var draft: PropertyValue?
    // Seeds from the definition's option order when the multi-select popover
    // opens; drag-reorder mutates this in-session. (Persisting the reordered
    // schema order from a value cell is deferred — see plan risks.)
    @State private var multiOptionOrder: [PropertyChipOption] = []

    var body: some View {
        if definition.type == .lastEditedTime {
            // Read-only — no tap gesture, no popover.
            PropertyCellDisplay(
                definition: definition,
                value: value,
                relationResolver: relationResolver
            )
        } else if definition.type == .checkbox {
            // Cell IS the toggle — tap flips immediately, no popover. Rendered
            // with the reusable PropertyCheckbox; a simultaneousGesture ensures
            // the tap fires even when Table's row-selection would swallow it.
            let checked: Bool = { if case .checkbox(let b) = value { return b }; return false }()
            PropertyCheckbox(
                // set is inert — the simultaneousGesture below is the single
                // commit path (it survives Table row-selection, and routing
                // the toggle through it avoids a double write). Display state
                // comes from `get`, which reflects the committed value.
                isChecked: Binding(get: { checked }, set: { _ in }),
                color: checked ? .green : .default,
                icon: "checkmark",
                size: 14
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { commit(.checkbox(!checked)) })
        } else if isStatusBox {
            // Status displayed as a checkbox: left-tap toggles between the
            // first "upcoming" option (unchecked) and the first "done" option
            // (checked); right-click opens the chip dropdown to pick any value.
            StatusCheckbox(value: currentStatusValue, groups: statusGroups, size: 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { toggleStatusBox() })
            .onSecondaryClick {
                draft = value
                isPresented = true
            }
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                editor
                    .presentationBackground(.clear)
                    .onDisappear { commit(draft) }
            }
        } else {
            Button {
                draft = value
                isPresented = true
            } label: {
                PropertyCellDisplay(
                    definition: definition,
                    value: value,
                    relationResolver: relationResolver
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                if isChipDropdownEditor {
                    // ChipDropdown is self-contained — it draws its own
                    // Liquid-Glass panel. Present it chromeless (clear the
                    // system popover background, no padding wrapper) so the
                    // popover doesn't stack a second container around it.
                    editor
                        .presentationBackground(.clear)
                        .onDisappear { commit(draft) }
                } else {
                    editor
                        .padding(12)
                        .frame(minWidth: 220)
                        .onDisappear { commit(draft) }
                }
            }
        }
    }

    /// Select / MultiSelect / Status use the self-contained `ChipDropdown`,
    /// which owns its own panel — so they present without the popover's
    /// chrome + padding (avoids a container-in-a-container).
    private var isChipDropdownEditor: Bool {
        switch definition.type {
        case .select, .multiSelect, .status: return true
        default: return false
        }
    }

    // MARK: - Status "Box" (checkbox) display

    /// A Status property whose Display As is `.box` renders as a checkbox —
    /// a binary projection over the status (first-`upcoming` ⇄ first-`done`).
    private var isStatusBox: Bool {
        definition.type == .status && (definition.displayAs ?? .select) == .box
    }

    private var statusGroups: [PropertyDefinition.StatusGroup] {
        definition.statusGroups ?? []
    }

    private var currentStatusValue: String? {
        if case .status(let v) = value { return v }
        return nil
    }

    /// The group the current value belongs to (nil when unset / not found).
    private func statusGroupID(of value: String?) -> PropertyDefinition.StatusGroupID? {
        guard let value else { return nil }
        for group in statusGroups where group.options.contains(where: { $0.value == value }) {
            return group.id
        }
        return nil
    }

    /// Checked ⟺ the current value is in the "done" group. Drives the binary
    /// left-tap toggle (done ⇄ upcoming). The tri-state *rendering* lives in
    /// `StatusCheckbox`; this is only the toggle pivot.
    private var isStatusChecked: Bool {
        statusGroupID(of: currentStatusValue) == .done
    }

    /// Toggle writes the FIRST option (schema sort order) of the target group:
    /// checked → first "upcoming"; unchecked → first "done".
    private func toggleStatusBox() {
        let targetGroup: PropertyDefinition.StatusGroupID = isStatusChecked ? .upcoming : .done
        guard let target = statusGroups.first(where: { $0.id == targetGroup })?.options.first else { return }
        commit(.status(target.value))
    }

    // MARK: - Per-type editor dispatch

    @ViewBuilder
    private var editor: some View {
        switch definition.type {
        case .number:
            numberEditor
        case .date:
            dateEditor(includesTime: false)
        case .datetime:
            dateEditor(includesTime: true)
        case .select:
            selectEditor
        case .multiSelect:
            multiSelectEditor
        case .status:
            statusEditor
        case .url:
            urlEditor
        case .relation:
            relationPlaceholder
        case .file:
            filePlaceholder
        case .checkbox, .lastEditedTime:
            EmptyView()  // handled above
        }
    }

    // MARK: - Editors

    @ViewBuilder
    private var numberEditor: some View {
        let binding = Binding<String>(
            get: {
                if case .number(let n) = draft { return String(n) }
                return ""
            },
            set: { newText in
                if let parsed = Double(newText.trimmingCharacters(in: .whitespaces)) {
                    draft = .number(parsed)
                } else if newText.isEmpty {
                    draft = .null
                }
            }
        )
        TextField("Number", text: binding)
            .textFieldStyle(.roundedBorder)
    }

    @ViewBuilder
    private func dateEditor(includesTime: Bool) -> some View {
        let binding = Binding<Date>(
            get: {
                if case .date(let d) = draft { return d }
                if case .datetime(let d) = draft { return d }
                return Date()
            },
            set: { newDate in
                draft = includesTime ? .datetime(newDate) : .date(newDate)
            }
        )
        DatePicker(
            "",
            selection: binding,
            displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date]
        )
        .labelsHidden()
        .datePickerStyle(.graphical)
    }

    @ViewBuilder
    private var selectEditor: some View {
        let opts = (definition.selectOptions ?? []).map { $0.asChipOption() }
        let current: String? = { if case .select(let v) = draft { return v }; return nil }()
        ChipDropdown(
            options: .constant(opts),
            selectionMode: .single,
            selectedIDs: current.map { Set([$0]) } ?? [],
            onPick: { opt in
                draft = .select(opt.id)
                isPresented = false
            },
            size: .compact
        )
    }

    @ViewBuilder
    private var multiSelectEditor: some View {
        let selected: [String] = { if case .multiSelect(let ids) = draft { return ids }; return [] }()
        ChipDropdown(
            options: $multiOptionOrder,
            selectionMode: .multi,
            selectedIDs: Set(selected),
            onPick: { opt in
                var ids = selected
                if let i = ids.firstIndex(of: opt.id) { ids.remove(at: i) } else { ids.append(opt.id) }
                draft = ids.isEmpty ? .null : .multiSelect(ids)
            },
            size: .compact
        )
        .onAppear { multiOptionOrder = (definition.selectOptions ?? []).map { $0.asChipOption() } }
    }

    @ViewBuilder
    private var statusEditor: some View {
        let groups = definition.statusGroups ?? []
        let opts: [PropertyChipOption] = groups.flatMap { g in
            g.options.map { $0.asChipOption(groupColor: g.color) }
        }
        let current: String? = { if case .status(let v) = draft { return v }; return nil }()
        ChipDropdown(
            options: .constant(opts),
            selectionMode: .single,
            selectedIDs: current.map { Set([$0]) } ?? [],
            onPick: { opt in
                draft = .status(opt.id)
                isPresented = false
            },
            size: .compact
        )
    }

    @ViewBuilder
    private var urlEditor: some View {
        let binding = Binding<String>(
            get: {
                if case .url(let u) = draft { return u.absoluteString }
                return ""
            },
            set: { newText in
                let trimmed = newText.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    draft = .null
                } else if let url = URL(string: trimmed) {
                    draft = .url(url)
                }
            }
        )
        TextField("https://…", text: binding)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
    }

    @ViewBuilder
    private var relationPlaceholder: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Relation editor")
                .font(.headline)
            Text("Inline relation picker ships in v0.3.1.x once IndexQuery flows to cell editors. Use the Item Window inspector to set relation values today.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 220, alignment: .leading)
        }
    }

    @ViewBuilder
    private var filePlaceholder: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("File attachments")
                .font(.headline)
            Text("Inline file editor ships in v0.3.1.x once AttachmentManager flows to cell editors. Use the Item Window inspector to attach files today.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 220, alignment: .leading)
        }
    }
}
