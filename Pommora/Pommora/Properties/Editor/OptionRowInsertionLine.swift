import SwiftUI

/// Drag-reorder insertion feedback shared by the two option editors
/// (`SelectOptionsEditor`, `StatusGroupsEditor`).
///
/// Both editors reorder small, static (non-scrolling) chip lists via the
/// `.draggable(String)` + `.dropDestination(for: String.self)` API. That API
/// commits a reorder when a row becomes the active drop target but gives no
/// built-in visual cue for *which* slot the drop will land in. This modifier
/// adds that cue: while a row is the active drop target it draws a thin
/// insertion line at the row's leading (top) edge — the exact slot the row's
/// own `.dropDestination` will commit to.
///
/// It deliberately does NOT touch the drop/commit path: the host row keeps its
/// existing `.dropDestination` and its existing reorder/confirmation semantics
/// (including `StatusGroupsEditor`'s cross-group `PendingMove` dialog). This is
/// visual feedback only — the line tracks the same `isTargeted` signal the drop
/// already reacts to, so the indicator and the commit can never disagree.
extension View {
    /// Draws a leading-edge insertion line over this row while `isActive` is
    /// true. Pair it with the row's existing `.dropDestination`, feeding that
    /// destination's `isTargeted` callback into a `@State` flag bound here.
    func optionRowInsertionLine(isActive: Bool) -> some View {
        overlay(alignment: .top) {
            OptionRowInsertionLine()
                .opacity(isActive ? 1 : 0)
                .animation(.easeOut(duration: 0.1), value: isActive)
        }
    }
}

/// The insertion line itself — a thin accent-tinted capsule sitting just above
/// a row, signalling "the dragged option will land here."
private struct OptionRowInsertionLine: View {
    @Environment(\.nexusAccent) private var accent

    var body: some View {
        Capsule()
            .fill(accent)
            .frame(height: 2)
            // Lift it into the inter-row gap (`PUI.Spacing.sm`) so it reads as a
            // gap between rows rather than a stripe across the chip.
            .offset(y: -(PUI.Spacing.sm / 2 + 1))
            .allowsHitTesting(false)
    }
}
