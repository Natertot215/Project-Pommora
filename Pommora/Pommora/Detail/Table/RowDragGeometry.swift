import CoreGraphics

/// Pure vertical hit-testing + insertion math for the custom table's row drag.
/// The mirror of `ColumnDragController`'s horizontal midpoint logic, rotated to
/// the Y axis: given the live row frames in a shared coordinate space and the
/// drop session's Y location, it resolves which row the location is over and
/// whether the insertion line lands ABOVE or BELOW that row (its vertical
/// midpoint splits it).
///
/// Kept free of actor isolation + SwiftUI types (`Sendable`, value-only) so it
/// unit-tests without disk or UI; the drag wiring lives on `CustomTableView`.
enum RowDragGeometry {

    /// A single hit-tested row: its stable id, its frame, and its index within
    /// the enclosing group's `items` order.
    struct RowFrame: Sendable, Equatable {
        let id: String
        let frame: CGRect
        let indexInGroup: Int
    }

    /// The insertion target a drop at `locationY` resolves to within one group's
    /// ordered `rows`. The index is in the group's ORIGINAL `items` coordinate
    /// space (pre-removal) — a drop in a row's top half targets that row's index,
    /// the bottom half targets the next index; past the last row's midpoint
    /// appends at `rows.count`. Returns nil when `rows` is empty.
    ///
    /// `rows` must be sorted by render order (ascending `minY`).
    static func insertionIndex(locationY: Double, rows: [RowFrame]) -> Int? {
        guard let last = rows.last else { return nil }
        for row in rows {
            let midpoint = row.frame.midY
            if locationY < midpoint { return row.indexInGroup }
        }
        return last.indexInGroup + 1
    }
}
