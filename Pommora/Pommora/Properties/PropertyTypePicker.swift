import SwiftUI

// MARK: - PropertyType + userCreatable

extension PropertyType {
    /// The 10 user-creatable property types. Excludes `.lastEditedTime`,
    /// which is auto-managed and cannot be created by the user.
    static let userCreatable: [PropertyType] = [
        .number,
        .checkbox,
        .date,
        .datetime,
        .select,
        .multiSelect,
        .status,
        .url,
        .relation,
        .file,
    ]

    /// SF Symbol icon for display in `PropertyTypePicker`.
    var pickerIcon: String {
        switch self {
        case .number:        return "number"
        case .checkbox:      return "checkmark.square"
        case .date:          return "calendar"
        case .datetime:      return "calendar.badge.clock"
        case .select:        return "chevron.up.chevron.down"
        case .multiSelect:   return "list.bullet"
        case .status:        return "circle.lefthalf.filled"
        case .url:           return "link"
        case .relation:      return "arrow.triangle.branch"
        case .lastEditedTime: return "clock"
        case .file:          return "paperclip"
        }
    }

    /// Display name shown in `PropertyTypePicker`.
    var displayName: String {
        switch self {
        case .number:        return "Number"
        case .checkbox:      return "Checkbox"
        case .date:          return "Date"
        case .datetime:      return "Date & Time"
        case .select:        return "Select"
        case .multiSelect:   return "Multi-Select"
        case .status:        return "Status"
        case .url:           return "URL"
        case .relation:      return "Relation"
        case .lastEditedTime: return "Last Edited Time"
        case .file:          return "File"
        }
    }
}

// MARK: - PropertyTypePicker

/// Vertical list picker for choosing one of the 10 user-creatable
/// `PropertyType`s. Each row: per-type SF Symbol + display name + trailing
/// chevron. No descriptions, no separator lines, no selection ring — the
/// commit-on-tap flow pops/routes immediately so the selected state is
/// invisible by design.
///
/// `.lastEditedTime` is excluded — auto-managed, not user-creatable.
struct PropertyTypePicker: View {
    @Binding var selected: PropertyType?
    let onSelect: (PropertyType) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(PropertyType.userCreatable, id: \.rawValue) { type in
                PropertyTypePickerRow(type: type) {
                    selected = type
                    onSelect(type)
                }
            }
        }
    }
}

// MARK: - PropertyTypePickerRow

private struct PropertyTypePickerRow: View {
    let type: PropertyType
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: PUI.Row.interSpacing) {
                Image(systemName: type.pickerIcon)
                    .font(PUI.Icon.leading)
                    .foregroundStyle(.primary)
                    .frame(width: PUI.Icon.leadingFrame)
                Text(type.displayName)
                    .font(PUI.Typography.row)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(PUI.Icon.chevron)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, PUI.Row.paddingHorizontal)
            .padding(.vertical, PUI.Row.paddingVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
