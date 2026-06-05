import SwiftUI

/// The shared Liquid-Glass panel surface for chip-dropdown popovers
/// (`ChipDropdown` + `ContextPicker`). Single source of truth for the
/// `.regularMaterial` fill + hairline border + clip. Callers own their own
/// padding and sizing (ChipDropdown is content-fixed; ContextPicker scrolls).
private struct ChipDropdownPanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
            .clipShape(.rect(cornerRadius: 12))
    }
}

extension View {
    /// Applies the shared chip-dropdown Liquid-Glass panel surface.
    func chipDropdownPanel() -> some View { modifier(ChipDropdownPanelBackground()) }
}
