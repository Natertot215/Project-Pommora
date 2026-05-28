import SwiftUI

extension View {
    /// Standard View Settings pane sizing: width-locked, height pinned to
    /// `PUI.Pane.minHeight`.
    ///
    /// NOTE: dynamic grow-to-`maxHeight`-then-scroll is a deliberate follow-up.
    /// Reliable content-sizing inside a macOS popover needs per-pane handling
    /// (greedy ScrollViews, pinned footers, Spacers) and visual verification;
    /// pinning to the minimum here preserves today's look with no regression
    /// while the dropdown work lands. `PUI.Pane.maxHeight` is reserved for it.
    func measuredPaneHeight() -> some View {
        frame(width: PUI.Pane.width, height: PUI.Pane.minHeight)
    }
}
