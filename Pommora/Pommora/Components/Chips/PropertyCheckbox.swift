import SwiftUI

/// Checkbox-shaped property control — a colored box with an SF Symbol when
/// checked. Used by Status (and boolean-ish) values in "Checkbox" display mode.
struct PropertyCheckbox: View {
    @Binding var isChecked: Bool
    var color: PropertyChipColor = .blue
    var icon: String = "checkmark"
    var size: CGFloat = 16

    var body: some View {
        Button {
            isChecked.toggle()
        } label: {
            box
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var box: some View {
        let shape = RoundedRectangle(cornerRadius: PUI.Radius.small, style: .continuous)
        if isChecked {
            Color.clear
                .frame(width: size, height: size)
                .coloredChip(color.swiftUIColor, in: shape)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: size * 0.65, weight: .bold))
                        .foregroundStyle(PUI.Tint.label(color.swiftUIColor))
                }
        } else {
            shape.fill(PUI.Tint.quaternary(PUI.Colors.chipBase))
                .frame(width: size, height: size)
        }
    }
}
