import SwiftUI

/// A selectable option row: optional leading icon, label, and a trailing checkmark
/// when selected. The shared primitive behind the View Settings pickers — property
/// pickers, sort presets, and disclosure-popover option lists.
struct SelectableOptionRow: View {
    let label: String
    var icon: String? = nil
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: PUI.Row.interSpacing) {
                if let icon {
                    Image(systemName: icon)
                        .font(PUI.Icon.leading)
                        .foregroundStyle(.secondary)
                        .frame(width: PUI.Icon.leadingFrame)
                }
                Text(label)
                    .font(PUI.Typography.row)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(PUI.Icon.chevron)
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, PUI.Row.paddingHorizontal)
            .padding(.vertical, PUI.Row.paddingVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
