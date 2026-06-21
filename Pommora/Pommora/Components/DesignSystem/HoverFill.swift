import SwiftUI

/// A self-contained hover background: a faint rounded-rect fill that fades in on
/// hover. Owns its own hover state, so a view that only needs "highlight on
/// hover" drops `.hoverFill()` instead of wiring `@State` + `.onHover` + a
/// `RoundedRectangle` by hand.
///
/// For hover that *also* drives other styling (a selected/today/current branch),
/// keep explicit `@State` and use `PUI.Fill.hover(_:)` for the color instead.
private struct HoverFill: ViewModifier {
    var cornerRadius: CGFloat = PUI.Radius.field
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(PUI.Fill.hover(isHovered))
            )
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// Faint rounded-rect fill on hover, with self-managed hover state.
    func hoverFill(cornerRadius: CGFloat = PUI.Radius.field) -> some View {
        modifier(HoverFill(cornerRadius: cornerRadius))
    }
}
