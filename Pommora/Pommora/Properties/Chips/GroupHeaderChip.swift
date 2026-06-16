import SwiftUI

extension PropertyDefinition {
    /// Locates the status option (and its owning group) for a stored value —
    /// the single lookup shared by the read-side cell renderer and the table's
    /// group-header chip.
    func statusOption(for value: String) -> (option: StatusOption, group: StatusGroup)? {
        guard let groups = statusGroups else { return nil }
        for group in groups {
            if let option = group.options.first(where: { $0.value == value }) {
                return (option, group)
            }
        }
        return nil
    }
}

/// Resolves the pill a Select / Status group header renders — label + colour,
/// pulled from the grouping property's schema. Returns nil for a property type
/// with no variant pill (Date / Checkbox), a structural group, or an empty /
/// unresolved bucket (those fall back to an icon + medium-weight title).
enum GroupHeaderChip {
    static func resolve(
        value: String?, grouping def: PropertyDefinition
    )
        -> (label: String, color: PropertyChipColor)?
    {
        guard let value else { return nil }
        switch def.type {
        case .select:
            guard let opt = def.selectOptions?.first(where: { $0.value == value }) else { return nil }
            return (opt.label, PropertyChipColor(selectColor: opt.color))
        case .status:
            guard let (option, group) = def.statusOption(for: value) else { return nil }
            return (option.label, PropertyChipColor(selectColor: option.color ?? group.color))
        default:
            return nil
        }
    }
}
