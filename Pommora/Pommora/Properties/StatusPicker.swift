import SwiftUI

/// Grouped status picker presented as a `Menu`. Sections mirror the three
/// fixed `StatusGroup` slots (upcoming / in_progress / done). Each option
/// renders a colored pill followed by its label. Single-pick only — selecting
/// a new option replaces the current selection.
struct StatusPicker: View {
    @Binding var selectedValue: String?
    let statusGroups: [PropertyDefinition.StatusGroup]
    let onSelect: (String?) -> Void

    var body: some View {
        Menu {
            ForEach(statusGroups) { group in
                Section(group.label) {
                    ForEach(group.options) { option in
                        Button {
                            selectedValue = option.value
                            onSelect(option.value)
                        } label: {
                            Label {
                                Text(option.label)
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(
                                        Color.forSelectColor(option.color ?? group.color)
                                    )
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                selectedValue = nil
                onSelect(nil)
            } label: {
                Label("Clear", systemImage: "xmark.circle")
            }
        } label: {
            statusLabel
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let value = selectedValue,
            let (option, group) = resolveOption(value)
        {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.forSelectColor(option.color ?? group.color))
                    .frame(width: 8, height: 8)
                Text(option.label)
                    .font(.callout)
            }
        } else {
            Text("—")
                .foregroundStyle(.tertiary)
        }
    }

    /// Resolves a status value string to its (option, group) pair.
    /// Returns `nil` if the value isn't found in the provided groups.
    func resolveOption(_ value: String) -> (PropertyDefinition.StatusOption, PropertyDefinition.StatusGroup)? {
        for group in statusGroups {
            if let option = group.options.first(where: { $0.value == value }) {
                return (option, group)
            }
        }
        return nil
    }

    /// Resolves the display color for a given status value.
    /// Falls back to group color when the option has no override.
    func resolvedColor(for value: String) -> Color {
        guard let (option, group) = resolveOption(value) else {
            return Color.forSelectColor(.gray)
        }
        return Color.forSelectColor(option.color ?? group.color)
    }
}

// MARK: - Color helper

extension Color {
    /// Maps a `PropertyDefinition.SelectColor` to a concrete SwiftUI `Color`.
    static func forSelectColor(_ color: PropertyDefinition.SelectColor) -> Color {
        switch color {
        case .gray:   return .gray
        case .brown:  return .brown
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .blue:   return .blue
        case .purple: return .purple
        case .pink:   return .pink
        case .red:    return .red
        }
    }
}
