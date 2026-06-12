import CoreGraphics
import Testing

@testable import Pommora

/// Covers `RowDragGeometry`'s pure vertical hit-test + insertion math — the
/// testable core of the Task-14 live-drag fix. `insertionIndex` maps a drop
/// session's Y location onto an insertion index within a group's ordered rows
/// via each row's vertical midpoint (top half → before, bottom half → after);
/// past the last row's midpoint appends. No disk, no UI. Mirrors
/// `ColumnDragMathTests`, rotated to the Y axis.
@Suite("RowDragGeometryTests") struct RowDragGeometryTests {

    // Three stacked 20pt rows starting at y=100: [100,120), [120,140), [140,160).
    // Midpoints: 110, 130, 150.
    private func row(_ id: String, y: CGFloat, index: Int) -> RowDragGeometry.RowFrame {
        RowDragGeometry.RowFrame(
            id: id, frame: CGRect(x: 0, y: y, width: 200, height: 20), indexInGroup: index)
    }

    private var rows: [RowDragGeometry.RowFrame] {
        [row("a", y: 100, index: 0), row("b", y: 120, index: 1), row("c", y: 140, index: 2)]
    }

    @Test func locationInTopHalfTargetsThatRow() {
        #expect(RowDragGeometry.insertionIndex(locationY: 105, rows: rows) == 0)
        #expect(RowDragGeometry.insertionIndex(locationY: 125, rows: rows) == 1)
        #expect(RowDragGeometry.insertionIndex(locationY: 145, rows: rows) == 2)
    }

    @Test func locationInBottomHalfTargetsNextRow() {
        #expect(RowDragGeometry.insertionIndex(locationY: 115, rows: rows) == 1)
        #expect(RowDragGeometry.insertionIndex(locationY: 135, rows: rows) == 2)
    }

    @Test func locationAboveFirstRowInsertsAtZero() {
        #expect(RowDragGeometry.insertionIndex(locationY: 50, rows: rows) == 0)
        #expect(RowDragGeometry.insertionIndex(locationY: 100, rows: rows) == 0)
    }

    @Test func locationPastLastRowAppends() {
        // Past the last midpoint (150) → append at last index + 1 (3).
        #expect(RowDragGeometry.insertionIndex(locationY: 155, rows: rows) == 3)
        #expect(RowDragGeometry.insertionIndex(locationY: 9999, rows: rows) == 3)
    }

    @Test func exactMidpointBoundaryTargetsNext() {
        // locationY == midpoint is NOT < midpoint, so it falls through to the next.
        #expect(RowDragGeometry.insertionIndex(locationY: 110, rows: rows) == 1)
        #expect(RowDragGeometry.insertionIndex(locationY: 130, rows: rows) == 2)
        #expect(RowDragGeometry.insertionIndex(locationY: 150, rows: rows) == 3)
    }

    @Test func emptyRowsReturnsNil() {
        #expect(RowDragGeometry.insertionIndex(locationY: 100, rows: []) == nil)
    }

    @Test func nonZeroBaseIndexIsPreserved() {
        // A group whose first item sits at index 5 in `items` — the returned
        // insertion index is in the group's own coordinate space, not 0-based.
        let offset = [row("x", y: 100, index: 5), row("y", y: 120, index: 6)]
        #expect(RowDragGeometry.insertionIndex(locationY: 105, rows: offset) == 5)
        #expect(RowDragGeometry.insertionIndex(locationY: 135, rows: offset) == 7)
    }
}
