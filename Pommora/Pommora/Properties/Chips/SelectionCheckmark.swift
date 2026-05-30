import SwiftUI

/// A multi-select badge: a filled blue rounded square with a white checkmark, shown
/// ONLY when `isSelected`. Unlike `PropertyCheckbox` — which always draws an (empty)
/// box when unchecked — an unselected slot here renders nothing but reserves its
/// width so row titles stay aligned. This is the selection affordance for the
/// relation value picker's leaf rows (icon + title + checkmark-on-selected); an
/// always-visible empty box would be visual noise in a multi-pick menu.
///
/// Visual mirrors `PropertyCheckbox`'s checked state (4-radius square, white bold
/// `checkmark` at `size * 0.65`) for consistency.
struct SelectionCheckmark: View {
    let isSelected: Bool
    var size: CGFloat = 18

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(isSelected ? Color.blue : Color.clear)
            .frame(width: size, height: size)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.65, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityHidden(true)
    }
}
