import SwiftUI

/// The shared Liquid-Glass panel surface for chip-dropdown popovers
/// (`ChipDropdown` + `ContextPicker`). Single source of truth for the
/// `.regularMaterial` fill + hairline border + clip. Callers own their own
/// padding and sizing (ChipDropdown is content-fixed; ContextPicker scrolls).
private struct ChipDropdownPanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: PUI.Radius.large, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: PUI.Radius.large, style: .continuous)
                            .strokeBorder(.white.opacity(0.10), lineWidth: PUI.Chip.strokeWidth)
                    )
            )
            .clipShape(.rect(cornerRadius: PUI.Radius.large))
    }
}

extension View {
    /// Applies the shared chip-dropdown Liquid-Glass panel surface.
    func chipDropdownPanel() -> some View { modifier(ChipDropdownPanelBackground()) }
}
