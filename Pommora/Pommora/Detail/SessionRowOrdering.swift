import Foundation

/// Pure session-local row-reorder logic for detail-pane Tables. Sidebar's
/// drag-reorder system writes to sidecar `order:` via the manager APIs;
/// the detail-pane's drag-reorder is intentionally session-only so the
/// two systems are independent. v0.5.0 saved-view-configs will migrate
/// detail-pane reorder to per-view-config overrides; this helper bridges
/// the gap.
enum SessionRowOrdering {
    /// Compute a new ordering by moving `movingID` to the position of
    /// `ontoID`, preserving every other ID's relative order. Returns the
    /// `base` unchanged when the move is a no-op (self-drop or unknown IDs).
    static func apply(base: [String], movingID: String, ontoID: String) -> [String] {
        guard movingID != ontoID else { return base }
        guard base.contains(movingID), base.contains(ontoID) else { return base }
        let originalTargetIdx = base.firstIndex(of: ontoID)!
        let originalSourceIdx = base.firstIndex(of: movingID)!
        var working = base
        working.removeAll { $0 == movingID }
        guard let targetIdx = working.firstIndex(of: ontoID) else { return base }
        // Drop onto a row: when moving downward, insert AFTER the target;
        // when moving upward, insert BEFORE. Matches the user's mental
        // model of "drop on the row to land just past it" in the down case.
        let insertIdx = originalTargetIdx > originalSourceIdx ? targetIdx + 1 : targetIdx
        working.insert(movingID, at: insertIdx)
        return working
    }
}
