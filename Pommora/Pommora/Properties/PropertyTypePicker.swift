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

/// Grid picker for choosing one of the 10 user-creatable `PropertyType`s.
///
/// `.lastEditedTime` is excluded — it is auto-managed and not user-creatable.
/// Single-pick: tapping calls `onSelect` with the chosen type.
struct PropertyTypePicker: View {
    @Binding var selected: PropertyType?
    let onSelect: (PropertyType) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 8)
    ]

    var body: some View {
        PropertyTypePickerGrid(
            selected: selected,
            onSelect: { type in
                selected = type
                onSelect(type)
            }
        )
    }
}

// MARK: - PropertyTypePickerGrid (isolated sub-view)

/// Isolated sub-view to avoid GRDB `SQLSpecificExpressible` overload conflicts
/// inside ForEach closures. Receives plain value types only.
private struct PropertyTypePickerGrid: View {
    let selected: PropertyType?
    let onSelect: (PropertyType) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(PropertyType.userCreatable, id: \.rawValue) { type in
                PropertyTypePickerCell(
                    type: type,
                    isSelected: selected == type,
                    onSelect: onSelect
                )
            }
        }
        .padding(4)
    }
}

// MARK: - PropertyTypePickerCell

private struct PropertyTypePickerCell: View {
    let type: PropertyType
    let isSelected: Bool
    let onSelect: (PropertyType) -> Void

    var body: some View {
        Button {
            onSelect(type)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: type.pickerIcon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(type.displayName)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.12)
                          : Color(.windowBackgroundColor).opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.clear,
                                lineWidth: 1.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
