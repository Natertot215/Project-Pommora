import SwiftUI

/// Shared chrome for the faint rounded-rect tag chips — padding/radius/fill/
/// optional hairline, all from `PUI`. (Strong colored chips use `.coloredChip`.)
struct ChipStyle {
    let paddingHorizontal: CGFloat
    let paddingVertical: CGFloat
    let cornerRadius: CGFloat
    let fill: AnyShapeStyle
    let stroke: AnyShapeStyle?
    let strokeWidth: CGFloat
}

extension ChipStyle {
    /// Relation / context tag — quaternary fill, tertiary hairline, card radius.
    static let referenceTag = ChipStyle(
        paddingHorizontal: PUI.Chip.tagPaddingHorizontal,
        paddingVertical: PUI.Chip.tagPaddingVertical,
        cornerRadius: PUI.Radius.card,
        fill: AnyShapeStyle(PUI.Tint.quaternary(PUI.Colors.chipBase)),
        stroke: AnyShapeStyle(PUI.Tint.tertiary(PUI.Colors.chipBase)),
        strokeWidth: PUI.Chip.strokeWidth
    )

    /// File-attachment tag — slightly stronger fill, no outline, tighter insets.
    static let fileTag = ChipStyle(
        paddingHorizontal: PUI.Chip.filePaddingHorizontal,
        paddingVertical: PUI.Chip.filePaddingVertical,
        cornerRadius: PUI.Radius.small,
        fill: AnyShapeStyle(PUI.Tint.tertiary(PUI.Colors.chipBase)),
        stroke: nil,
        strokeWidth: 0
    )
}

private struct ChipStyleModifier: ViewModifier {
    let style: ChipStyle

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, style.paddingHorizontal)
            .padding(.vertical, style.paddingVertical)
            .background(style.fill, in: .rect(cornerRadius: style.cornerRadius, style: .continuous))
            .overlay {
                if let stroke = style.stroke {
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .strokeBorder(stroke, lineWidth: style.strokeWidth)
                }
            }
    }
}

extension View {
    /// Apply the shared faint-tag chip chrome.
    func chipStyle(_ style: ChipStyle) -> some View {
        modifier(ChipStyleModifier(style: style))
    }

    /// Strong colored-chip chrome (fill + full-color border). Pair with
    /// `.foregroundStyle(PUI.Tint.label(base))` on the content.
    func coloredChip<S: InsettableShape>(_ base: Color, in shape: S) -> some View {
        background(shape.fill(PUI.Tint.primary(base)))
            .overlay(shape.strokeBorder(base, lineWidth: PUI.Chip.borderWidth))
    }
}
