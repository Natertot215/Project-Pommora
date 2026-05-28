import Foundation

/// Bridges the UI palette (`PropertyChipColor`, 12 cases) and the persistence
/// palette (`PropertyDefinition.SelectColor`, 9 cases), plus the option →
/// `PropertyChipOption` conversions the inline `ChipDropdown` consumes.
///
/// Single source of truth — previously the reverse-map was copy-pasted as a
/// private `selectColor(from:)` in both `SelectOptionsEditor` and
/// `StatusGroupsEditor`.
extension PropertyChipColor {
    /// Reverse of `init(selectColor:)`. Maps the UI palette back to the
    /// 9-case persistence enum; cases persistence lacks (`.teal`, `.indigo`)
    /// fall to the nearest match; `.default` / `.accent` → nil ("no color").
    func toSelectColor() -> PropertyDefinition.SelectColor? {
        switch self {
        case .default, .accent: return nil
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .teal: return .blue
        case .indigo: return .purple
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        }
    }
}

extension PropertyDefinition.SelectOption {
    /// Render this option as a `ChipDropdown` row option.
    func asChipOption() -> PropertyChipOption {
        PropertyChipOption(id: value, label: label, color: PropertyChipColor(selectColor: color))
    }
}

extension PropertyDefinition.StatusOption {
    /// Render this status option as a `ChipDropdown` row option. Status
    /// options inherit the group color when they don't override it.
    func asChipOption(groupColor: PropertyDefinition.SelectColor) -> PropertyChipOption {
        PropertyChipOption(id: value, label: label, color: PropertyChipColor(selectColor: color ?? groupColor))
    }
}
