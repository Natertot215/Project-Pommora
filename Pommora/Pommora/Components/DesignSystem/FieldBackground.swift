import SwiftUI

/// The unified input-field / icon-button backdrop for the popover-family
/// surfaces (View Settings panes, OptionEditPopover, StorageMenuRoot header).
///
/// **Why this exists:** every editable field used to inline its own
/// `Capsule().fill(Color.primary.opacity(0.06))` "pill" — a made-up value,
/// copy-pasted across files, that never matched the native page inspector. The
/// baseline (2026-05-27) replaces all of them with the inspector's own system
/// grouped-Form fill (`PUI.Fill.field`) on a rounded-rect (NOT a pill), routed
/// through this single modifier so the look converges and a future tweak is a
/// one-token edit.
///
/// **Usage** — apply *after* the field's own internal padding so the backdrop
/// wraps the padded content (padding → background ordering):
/// ```swift
/// TextField("Title", text: $draft)
///     .textFieldStyle(.plain)
///     .padding(.horizontal, PUI.Spacing.lg)
///     .padding(.vertical, PUI.Spacing.md)
///     .fieldBackground()
/// ```
struct FieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            PUI.Fill.field,
            in: .rect(cornerRadius: PUI.Radius.field, style: .continuous)
        )
    }
}

extension View {
    /// Apply the unified field backdrop (`PUI.Fill.field` on a
    /// `PUI.Radius.field` rounded-rect). See `FieldBackground`.
    func fieldBackground() -> some View {
        modifier(FieldBackground())
    }
}
