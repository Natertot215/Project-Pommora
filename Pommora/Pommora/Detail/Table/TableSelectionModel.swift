import Foundation

/// Selection + keyboard-navigation state for the custom table — the row-selection
/// machinery the native `Table` gave for free (single / ⌘-toggle / ⇧-range, arrow
/// nav, type-select). Pure value math (range/anchor, move, type-select target)
/// lives in side-effect-free methods so `TableSelectionModelTests` can exercise
/// them without SwiftUI.
///
/// `order` is the FLATTENED visible row order — the linear sequence of page ids
/// exactly as the table renders them (groups in resolved order, items within a
/// group, then each child group's items for vault scope). The renderer keeps it
/// in sync from the same `[ResolvedGroup]` it draws. ⇧-range and arrow nav both
/// walk this list, so they always match what's on screen.
@MainActor
@Observable
final class TableSelectionModel {
    /// Currently-selected page ids.
    private(set) var selection: Set<String> = []

    /// The range pivot — set by plain/⌘ click + arrow moves, extended-from by ⇧.
    private(set) var anchor: String?

    /// Flattened visible row order (page ids), kept in render order by the view.
    var order: [String] = []

    // MARK: - Click kinds

    /// The three click intents, modeled as a closed set so the click handler
    /// switches exhaustively rather than branching on loose modifier booleans.
    enum ClickKind {
        case plain  // replace selection with this id
        case toggle  // ⌘ — add/remove this id
        case range  // ⇧ — contiguous anchor→id span
    }

    /// Arrow-move direction, paired with whether ⇧ is extending the range.
    enum MoveDirection {
        case up
        case down
    }

    // MARK: - Click

    /// Apply a click of `kind` on `id`. Mutates `selection` + `anchor`.
    func click(_ id: String, kind: ClickKind) {
        switch kind {
        case .plain:
            selection = [id]
            anchor = id
        case .toggle:
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchor = id
        case .range:
            selection = rangeSelection(to: id)
        // Anchor intentionally stays put so a subsequent ⇧-click re-spans
        // from the original pivot (matching Finder / native Table).
        }
    }

    /// The contiguous span (in flattened `order`) from `anchor` to `id`,
    /// inclusive. Falls back to just `id` when there's no anchor or either id is
    /// off-list.
    func rangeSelection(to id: String) -> Set<String> {
        guard let anchor,
            let from = order.firstIndex(of: anchor),
            let to = order.firstIndex(of: id)
        else { return [id] }
        let span = from <= to ? from...to : to...from
        return Set(order[span])
    }

    // MARK: - Keyboard move

    /// Move selection one row in `direction` within flattened `order`. When
    /// `extend` is true the selection grows as a ⇧-range from `anchor` to the new
    /// row; otherwise it collapses to the single new row (and re-anchors there).
    /// Returns the newly-focused id (for scroll-into-view), or nil if no move
    /// was possible (empty order).
    @discardableResult
    func move(_ direction: MoveDirection, extend: Bool) -> String? {
        guard !order.isEmpty else { return nil }
        let nextID = neighbor(direction)
        guard let nextID else { return nil }
        if extend {
            if anchor == nil { anchor = nextID }
            selection = rangeSelection(to: nextID)
        } else {
            selection = [nextID]
            anchor = nextID
        }
        return nextID
    }

    /// The id one step from the current focus in `direction`. Focus is the last
    /// moved-to row, approximated by `anchor`'s position; with no anchor a Down
    /// starts at the first row and an Up at the last.
    private func neighbor(_ direction: MoveDirection) -> String? {
        guard let anchor, let idx = order.firstIndex(of: anchor) else {
            return direction == .down ? order.first : order.last
        }
        switch direction {
        case .up: return idx > 0 ? order[idx - 1] : order.first
        case .down: return idx < order.count - 1 ? order[idx + 1] : order.last
        }
    }

    // MARK: - Type-select

    /// The first row id whose `title(for:)` starts with `prefix` (case-insensitive),
    /// scanning flattened `order`. Pure: the view supplies the id→title lookup.
    /// Returns nil when nothing matches.
    func typeSelectTarget(prefix: String, title: (String) -> String?) -> String? {
        guard !prefix.isEmpty else { return nil }
        let needle = prefix.lowercased()
        return order.first { id in
            (title(id) ?? "").lowercased().hasPrefix(needle)
        }
    }

    /// The last-selected row for the Return / open intent: the anchor if it's in
    /// the selection, else any selected id (stable by `order`).
    var openTargetID: String? {
        if let anchor, selection.contains(anchor) { return anchor }
        return order.first { selection.contains($0) }
    }
}
