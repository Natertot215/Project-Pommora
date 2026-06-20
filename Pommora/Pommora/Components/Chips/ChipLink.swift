import SwiftUI

/// **Intentionally-dormant design asset (PagesV2 V7).** The chip-link visual
/// design survives here and in Figma; it is wired to nothing. The engine-side
/// chip pipeline (tokenizer, styler, CoreGraphics renderer) was retired
/// wholesale — this file is the single canonical home of the chip's design,
/// staged in the Component Library so it stays browsable and ready to pull
/// back into production if a chip-style render is ever needed again.
///
/// **Design:** an inline text highlight — quaternary fill + thin tertiary
/// outline — that follows the text line height so it reads as marked text
/// rather than a button placed in-line. Icon + title in body font, no extra
/// vertical padding (height = line height).
///
/// Stays at `Properties/Chips/`, beside `ContextChip`. Do NOT move.
struct ChipLink: View {
    // Canonical chip design tokens (folded in from the retired engine-side
    // ChipLinkMetrics so the values survive the chip pipeline's removal).
    static let horizontalPadding: CGFloat = 4
    static let iconTitleGap: CGFloat = 3
    static let cornerRadius: CGFloat = 3
    static let outlineWidth: CGFloat = 0.5

    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: Self.iconTitleGap) {
            Image(systemName: icon)
                .imageScale(.small)
            Text(title)
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .font(.body)
        .padding(.horizontal, Self.horizontalPadding)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(.quaternary)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .strokeBorder(.tertiary, lineWidth: Self.outlineWidth)
                )
        )
    }
}
