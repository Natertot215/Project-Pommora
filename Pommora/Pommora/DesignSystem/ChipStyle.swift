import SwiftUI

/// The shared chrome for the rounded-rect chip family (`Components/Chips/`) —
/// padding, corner radius, translucent fill, optional hairline outline. Mirrors
/// the `.fieldBackground()` precedent: every value comes from `PUI`, so the chip
/// bodies stay pure content and a restyle is a single-token edit.
///
/// **Not** for the saturated `PropertyChip` pill (a Capsule with a colored fill
/// + white text); that carries its own `Size` enum. This is the neutral-tag
/// chrome the relation / file / link chips share.
///
/// Apply *after* the chip's own internal `HStack` content so the backdrop wraps
/// the padded content (padding → background ordering).
struct ChipStyle: Equatable {
    let paddingHorizontal: CGFloat
    let paddingVertical: CGFloat
    let cornerRadius: CGFloat
    let fill: AnyShapeStyle
    let stroke: AnyShapeStyle?
    let strokeWidth: CGFloat

    static func == (lhs: ChipStyle, rhs: ChipStyle) -> Bool {
        lhs.paddingHorizontal == rhs.paddingHorizontal
            && lhs.paddingVertical == rhs.paddingVertical
            && lhs.cornerRadius == rhs.cornerRadius
            && lhs.strokeWidth == rhs.strokeWidth
            && (lhs.stroke == nil) == (rhs.stroke == nil)
    }
}

extension ChipStyle {
    /// Relation / context tag — `.quinary` fill, hairline `.separator` outline,
    /// card radius. The look every relation surface routes through.
    static let referenceTag = ChipStyle(
        paddingHorizontal: PUI.Chip.tagPaddingHorizontal,
        paddingVertical: PUI.Chip.tagPaddingVertical,
        cornerRadius: PUI.Radius.card,
        fill: PUI.Tint.tag,
        stroke: PUI.Tint.tagStroke,
        strokeWidth: PUI.Chip.strokeWidth
    )

    /// File-attachment tag — brighter `.quaternarySystemFill`, no outline,
    /// small radius + tighter insets. The attachment-language affordance.
    static let fileTag = ChipStyle(
        paddingHorizontal: PUI.Chip.filePaddingHorizontal,
        paddingVertical: PUI.Chip.filePaddingVertical,
        cornerRadius: PUI.Radius.small,
        fill: PUI.Tint.fileTag,
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
            .background(
                style.fill,
                in: .rect(cornerRadius: style.cornerRadius, style: .continuous)
            )
            .overlay {
                if let stroke = style.stroke {
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .strokeBorder(stroke, lineWidth: style.strokeWidth)
                }
            }
    }
}

extension View {
    /// Apply the shared rounded-rect chip chrome. See `ChipStyle`.
    func chipStyle(_ style: ChipStyle) -> some View {
        modifier(ChipStyleModifier(style: style))
    }
}
