import SwiftUI

/// The standard tri-state checkbox projection of a Status value — the canonical
/// rendering for a Status property whose "Display As" is `.box`.
///
/// State mapping (single source of truth; do not re-implement at call sites):
///   - `upcoming` / unset → empty checkbox (default fill; the value's color is
///     intentionally ignored — empty always reads as the neutral empty box)
///   - `in_progress`      → the value's color + `minus` (partial)
///   - `done`             → the value's color + `checkmark`
///
/// Pure visual + mapping. Interaction (left-tap toggle, right-click picker)
/// is the host's concern because it touches the data layer — see
/// `PropertyCellEditor`. Built on the reusable `PropertyCheckbox`.
struct StatusCheckbox: View {
    /// The current status value (an option's `value`), or nil when unset.
    let value: String?
    /// The property's status groups, used to resolve the value's group + color.
    let groups: [PropertyDefinition.StatusGroup]
    var size: CGFloat = 14

    var body: some View {
        PropertyCheckbox(
            isChecked: .constant(isFilled),
            color: color,
            icon: icon,
            size: size
        )
    }

    /// The group the current value belongs to (nil when unset / not found).
    private var groupID: PropertyDefinition.StatusGroupID? {
        guard let value else { return nil }
        for group in groups where group.options.contains(where: { $0.value == value }) {
            return group.id
        }
        return nil
    }

    /// Filled (color + icon) for in-progress and done; empty otherwise.
    private var isFilled: Bool { groupID == .done || groupID == .inProgress }

    /// Done → checkmark; in-progress → minus. Unused when empty.
    private var icon: String { groupID == .done ? "checkmark" : "minus" }

    /// The value's resolved chip color (option override, else group default).
    /// `PropertyCheckbox` ignores this when unchecked (draws its default fill).
    private var color: PropertyChipColor {
        guard let value else { return .default }
        for group in groups {
            if let opt = group.options.first(where: { $0.value == value }) {
                return PropertyChipColor(selectColor: opt.color ?? group.color)
            }
        }
        return .default
    }
}
