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
///   - select → inline Picker bound to selectOptions
///   - multiSelect → MultiSelectChips (existing component)
///   - status → StatusPicker (existing component)
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

    var body: some View {
        if definition.type == .lastEditedTime {
            // Read-only — no tap gesture, no popover.
            PropertyCellDisplay(
                definition: definition,
                value: value,
                relationResolver: relationResolver
            )
        } else if definition.type == .checkbox {
            // Cell IS the toggle — tap flips immediately, no popover.
            Button {
                let current: Bool = {
                    if case .checkbox(let b) = value { return b }
                    return false
                }()
                commit(.checkbox(!current))
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
                editor
                    .padding(12)
                    .frame(minWidth: 220)
                    .onDisappear {
                        commit(draft)
                    }
            }
        }
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
        let options = definition.selectOptions ?? []
        let binding = Binding<String?>(
            get: {
                if case .select(let v) = draft { return v }
                return nil
            },
            set: { newValue in
                if let v = newValue {
                    draft = .select(v)
                } else {
                    draft = .null
                }
            }
        )
        Picker("Select", selection: binding) {
            Text("None").tag(String?.none)
            ForEach(options) { opt in
                Text(opt.label).tag(String?.some(opt.value))
            }
        }
        .labelsHidden()
        .pickerStyle(.inline)
    }

    @ViewBuilder
    private var multiSelectEditor: some View {
        let options = (definition.selectOptions ?? []).map(\.value)
        let binding = Binding<[String]>(
            get: {
                if case .multiSelect(let ids) = draft { return ids }
                return []
            },
            set: { newIDs in
                draft = newIDs.isEmpty ? .null : .multiSelect(newIDs)
            }
        )
        MultiSelectChips(options: options, selected: binding, allowsAddingOptions: false)
    }

    @ViewBuilder
    private var statusEditor: some View {
        let groups = definition.statusGroups ?? []
        let binding = Binding<String?>(
            get: {
                if case .status(let v) = draft { return v }
                return nil
            },
            set: { newValue in
                if let v = newValue {
                    draft = .status(v)
                } else {
                    draft = .null
                }
            }
        )
        StatusPicker(
            selectedValue: binding,
            statusGroups: groups,
            onSelect: { _ in }
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
