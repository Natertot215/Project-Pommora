import SwiftUI

/// A lean selection tick for the relation value picker's leaf rows: a bare
/// `checkmark` glyph in the app accent color (`.tint`), shown ONLY when
/// `isSelected`. There is no box — an unselected slot renders nothing but reserves
/// its width (via `opacity`, not removal) so row titles stay aligned.
///
/// Deliberately NOT a checkbox: `PropertyCheckbox` always draws a box (the right
/// model for a boolean field), but in a multi-pick menu an always-visible empty box
/// reads as noise. A clean accent check reads simply as "picked."
struct SelectionCheckmark: View {
    let isSelected: Bool
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.85, weight: .semibold))
            .foregroundStyle(.tint)
            .frame(width: size, height: size)
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(true)
    }
}
