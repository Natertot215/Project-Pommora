import SwiftUI

/// The standard divider for settings-popover panes: a system `Divider` inset
/// to the content rail (`PUI.Pane.contentPadding`). Use this for EVERY divider
/// in the dropdown settings so horizontal insets stay uniform across panes
/// (2026-05-27 universal divider standard — it must align to the same rail as
/// rows + the "New property"-style footers). Callers add vertical padding
/// where a gap is wanted (e.g. the field↔content divider adds 5pt).
struct PaneDivider: View {
    /// Horizontal inset to the content rail. Defaults to the standard pane rail;
    /// pass a different rail for dropdowns whose rows sit at another inset.
    var inset: CGFloat = PUI.Pane.contentPadding
    var body: some View {
        Divider()
            .padding(.horizontal, inset)
    }
}
