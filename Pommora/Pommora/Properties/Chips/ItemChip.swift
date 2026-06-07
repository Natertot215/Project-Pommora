import SwiftUI

/// **The rendering primitive for resolved `{{Item}}` connections.** An inline
/// text highlight — quaternary fill + thin tertiary outline — that follows the
/// text line height so it reads as marked text rather than a button placed
/// in-line. Mirrors the CoreGraphics render in the page editor
/// (`MarkdownTextLayoutFragment.drawItemChips`).
///
/// **Design:** Title in body font, no extra vertical padding (height = line
/// height), 4pt horizontal padding each side, corner radius 3.
///
/// **Data-model contract:** `title` resolves from the LINKED Item (via
/// `IndexQuery`). Pre-resolved `String`; purely visual.
///
/// Stays at `Properties/Chips/`, beside `ContextChip`. Do NOT move.
struct ItemChip: View {
    let title: String

    var body: some View {
        Text(title)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .font(.body)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.quaternary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(.tertiary, lineWidth: 0.5)
                    )
            )
    }
}
