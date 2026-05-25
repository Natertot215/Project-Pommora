import SwiftUI

struct PropertyEditorRow: View {
    let definition: PropertyDefinition
    @Binding var value: PropertyValue

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
        case .date:
            dateEditor(includeTime: false)
        case .datetime:
            dateEditor(includeTime: true)
        case .select:
            selectEditor
        case .multiSelect:
            multiSelectEditor
        case .relation:
            Text("Relation editor coming v0.3.0").font(.caption).foregroundStyle(.tertiary)
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

    private func dateEditor(includeTime: Bool) -> some View {
        DatePicker(
            "",
            selection: Binding(
                get: {
                    if case .date(let d) = value { return d }
                    if case .datetime(let d) = value { return d }
                    return Date()
                },
                set: { value = includeTime ? .datetime($0) : .date($0) }
            ),
            displayedComponents: includeTime ? [.date, .hourAndMinute] : [.date]
        )
        .labelsHidden()
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

    private var statusEditor: some View {
        let currentValue: String = {
            if case .status(let s) = value { return s }
            return ""
        }()
        return Text("Status: \(currentValue)")
            .font(.caption)
            .foregroundStyle(.secondary)
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
