import SwiftUI

/// A lean accent-colored selection tick for the relation value picker's leaf rows: a
/// bare `checkmark` glyph in the app accent color (`.tint`). The caller renders it
/// ONLY on selected rows, so an unselected row gives its full width to the label and
/// the check materializes at the trailing edge only when the row is picked.
///
/// Deliberately NOT a checkbox: `PropertyCheckbox` always draws a box (the right
/// model for a boolean field), but in a multi-pick menu a clean accent check reads
/// simply as "picked."
struct SelectionCheckmark: View {
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.85, weight: .semibold))
            .foregroundStyle(.tint)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
