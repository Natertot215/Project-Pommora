import Foundation

/// Pure session-local row-reorder logic for detail-pane Tables. Sidebar's
/// drag-reorder system writes to sidecar `order:` via the manager APIs;
/// the detail-pane's drag-reorder is intentionally session-only so the
/// two systems are independent. v0.5.0 saved-view-configs will migrate
/// detail-pane reorder to per-view-config overrides; this helper bridges
/// the gap.
enum SessionRowOrdering {
    /// Move `movingID` so it lands at `toOffset` within `base` — the insertion
    /// index SwiftUI's row `dropDestination(for:action:)` reports (measured
    /// against the array *before* the moved row is removed). Every other ID
    /// keeps its relative order. Returns `base` unchanged for an unknown ID or
    /// a no-op move (dropping a row onto its own slot).
    static func move(base: [String], movingID: String, toOffset: Int) -> [String] {
        guard let from = base.firstIndex(of: movingID) else { return base }
        let target = min(max(toOffset, 0), base.count)
        // Removing the row first shifts every later index down by one, so a
        // target past the original position lands one slot earlier.
        let insertAt = target > from ? target - 1 : target
        guard insertAt != from else { return base }
        var working = base
        working.remove(at: from)
        working.insert(movingID, at: insertAt)
        return working
    }

    /// Layer a session-local order (`sessionOrder`, a list of row IDs) over the
    /// manager's natural order (`base`). Rows named in `sessionOrder` render in
    /// that sequence; rows added since the last reorder append at the end. Nil
    /// session order → `base` unchanged. Shared by every detail view's `rows`.
    static func reconcile<Element: Identifiable>(
        base: [Element], sessionOrder: [String]?
    ) -> [Element] where Element.ID == String {
        guard let sessionOrder else { return base }
        let byID = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = sessionOrder.compactMap { byID[$0] }
        let known = Set(sessionOrder)
        return ordered + base.filter { !known.contains($0.id) }
    }
}
