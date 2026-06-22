import SwiftUI

/// A labeled on/off row: optional leading icon, label, and a trailing switch. The
/// shared primitive behind the View Settings toggles. `secondary` renders a smaller,
/// muted sub-row; `isEnabled == false` mutes the row tonally and disables the switch.
struct LabeledToggleRow: View {
    let label: String
    var icon: String? = nil
    @Binding var isOn: Bool
    var isEnabled: Bool = true
    var secondary: Bool = false

    private var contentStyle: AnyShapeStyle {
        if !isEnabled { return AnyShapeStyle(.tertiary) }
        return secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
    }

    var body: some View {
        HStack(spacing: PUI.Row.interSpacing) {
            if let icon {
                Image(systemName: icon)
                    .font(PUI.Icon.leading)
                    .foregroundStyle(contentStyle)
                    .frame(width: PUI.Icon.leadingFrame)
            }
            Text(label)
                .font(secondary ? .subheadline : PUI.Typography.row)
                .foregroundStyle(contentStyle)
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(!isEnabled)
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, secondary ? PUI.Spacing.xs : PUI.Row.paddingVertical)
    }
}
