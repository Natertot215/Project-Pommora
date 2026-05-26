import SwiftUI

/// A checkbox-shaped property control. Standard checkbox dimensions, custom
/// iconography (SF Symbol shown when checked), and custom fill color when
/// checked. Used wherever a Status property or similar boolean-ish chip
/// value renders in "Checkbox" display mode (a per-view setting that ships
/// alongside saved-view-configs in v0.5.0).
///
/// Distinct from `PropertyChip` because this is a checkbox, not a pill — the
/// shapes serve different mental models. Same `PropertyChipColor` palette
/// drives the fill when checked.
///
/// **Naming note (2026-05-25):** what was previously called the `.box`
/// variant of `PropertyChip` is actually a `PropertyCheckbox` — they are
/// different components, not variants of the same thing. The chip family
/// is text/icon-only pills; the checkbox family is the checkbox primitive.
struct PropertyCheckbox: View {
    @Binding var isChecked: Bool
    var color: PropertyChipColor = .blue
    var icon: String = "checkmark"   // SF Symbol shown when checked
    var size: CGFloat = 16           // standard checkbox dimension

    var body: some View {
        Button {
            isChecked.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    isChecked
                        ? color.swiftUIColor
                        : Color(.tertiaryLabelColor).opacity(0.25)
                )
                .frame(width: size, height: size)
                .overlay {
                    if isChecked {
                        Image(systemName: icon)
                            .font(.system(size: size * 0.65, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
