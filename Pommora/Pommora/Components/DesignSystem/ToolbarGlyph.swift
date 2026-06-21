import SwiftUI

/// The unified glyph styling for window-toolbar buttons — the primary-action
/// cluster (Views, settings, nav, inspector) and the navigation Back / Forward
/// pair.
///
/// **Why this exists:** every toolbar button used to inline the identical
/// `.font(.system(size: 12, weight: .medium)).frame(width:).contentShape(Rectangle())`
/// triple — the same three modifiers copy-pasted across five button files. This
/// routes them through one modifier so the look converges and a future tweak is
/// a single edit. Height is deliberately NOT set: it's system-owned by the
/// default toolbar button style (the fix that stopped the buttons fighting the
/// system and squishing).
///
/// **Usage:**
/// ```swift
/// Image(systemName: "slider.horizontal.3")
///     .toolbarGlyph(width: PUI.Icon.toolbarActionFrame)
/// ```
struct ToolbarGlyph: ViewModifier {
    let width: CGFloat
    func body(content: Content) -> some View {
        content
            .font(PUI.Icon.toolbarAction)
            .frame(width: width)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Apply the unified toolbar-glyph styling (`PUI.Icon.toolbarAction` font in
    /// a fixed-`width` hit target; system-owned height). See `ToolbarGlyph`.
    func toolbarGlyph(width: CGFloat) -> some View {
        modifier(ToolbarGlyph(width: width))
    }
}
