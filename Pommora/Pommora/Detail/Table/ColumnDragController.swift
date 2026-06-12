import Foundation

/// Pure column-drag math for the custom table's header drag-reorder. The only
/// testable core of Task 10's reorder interaction — given the live column
/// geometry (x-offsets/widths via prefix sums) and the drag's x-location,
/// it returns the insertion index in `propertyOrder` and the reordered array.
///
/// Kept free of actor isolation + UI types (`Sendable`, value-only) so it unit-
/// tests without disk or SwiftUI; the gesture wiring lives on `TableHeaderRow`.
enum ColumnDragController {
    /// The target insertion index for a column dragged to `dragX` (a content-x
    /// coordinate in the same space as the column prefix sums).
    ///
    /// Columns are described by their left-edge x-offsets (`offsets[i]`) and
    /// `widths[i]`; each column's midpoint splits it — a drag whose x sits in
    /// the LEFT half of column `i` targets index `i`, the RIGHT half targets
    /// `i + 1`. This yields the natural "insert before/after the hovered
    /// column" feel and handles both ends: dragging before the first column's
    /// midpoint returns 0, dragging past the last column's midpoint returns
    /// `count` (append).
    ///
    /// `offsets` + `widths` must be equal length and in render order. An empty
    /// table returns 0.
    static func insertionIndex(dragX: Double, offsets: [Double], widths: [Double]) -> Int {
        let count = min(offsets.count, widths.count)
        guard count > 0 else { return 0 }
        for i in 0..<count {
            let midpoint = offsets[i] + widths[i] / 2
            if dragX < midpoint { return i }
        }
        return count
    }

    /// Reorders `order` by moving the element at `from` to `insertion` — the
    /// insertion index being expressed in the ORIGINAL (pre-removal) coordinate
    /// space returned by `insertionIndex`. Returns `order` unchanged when either
    /// index is out of range or the move is a no-op.
    static func reorder(_ order: [String], from: Int, to insertion: Int) -> [String] {
        guard order.indices.contains(from) else { return order }
        let clamped = max(0, min(insertion, order.count))
        // Removing `from` shifts every later index down by one; an insertion
        // point past `from` must compensate.
        let target = clamped > from ? clamped - 1 : clamped
        if target == from { return order }
        var result = order
        let moved = result.remove(at: from)
        result.insert(moved, at: min(target, result.count))
        return result
    }
}
