import Foundation
import Testing

@testable import Pommora

/// Covers `ColumnDragController`'s pure header drag-reorder math — the testable
/// core of Task 10. `insertionIndex` maps a content-x drag location onto a
/// target insertion index via per-column midpoints (left half → before, right
/// half → after); `reorder` moves a column to that index, compensating for the
/// removal shift. No disk, no UI.
@Suite("ColumnDragMathTests") struct ColumnDragMathTests {

    // Three columns: [0,100), [100,260), [260,440). Midpoints: 50, 180, 350.
    private let offsets: [Double] = [0, 100, 260]
    private let widths: [Double] = [100, 160, 180]

    // MARK: - insertionIndex

    @Test func dragInLeftHalfTargetsThatColumn() {
        #expect(ColumnDragController.insertionIndex(dragX: 10, offsets: offsets, widths: widths) == 0)
        #expect(ColumnDragController.insertionIndex(dragX: 120, offsets: offsets, widths: widths) == 1)
        #expect(ColumnDragController.insertionIndex(dragX: 300, offsets: offsets, widths: widths) == 2)
    }

    @Test func dragInRightHalfTargetsNextColumn() {
        #expect(ColumnDragController.insertionIndex(dragX: 90, offsets: offsets, widths: widths) == 1)
        #expect(ColumnDragController.insertionIndex(dragX: 250, offsets: offsets, widths: widths) == 2)
    }

    @Test func dragBeforeFirstColumnInsertsAtZero() {
        #expect(ColumnDragController.insertionIndex(dragX: -50, offsets: offsets, widths: widths) == 0)
        #expect(ColumnDragController.insertionIndex(dragX: 0, offsets: offsets, widths: widths) == 0)
    }

    @Test func dragPastLastColumnAppends() {
        // Past the last midpoint (350) → append at count (3).
        #expect(ColumnDragController.insertionIndex(dragX: 400, offsets: offsets, widths: widths) == 3)
        #expect(ColumnDragController.insertionIndex(dragX: 9999, offsets: offsets, widths: widths) == 3)
    }

    @Test func exactMidpointBoundaryTargetsNext() {
        // dragX == midpoint is NOT < midpoint, so it falls through to the next.
        #expect(ColumnDragController.insertionIndex(dragX: 50, offsets: offsets, widths: widths) == 1)
        #expect(ColumnDragController.insertionIndex(dragX: 180, offsets: offsets, widths: widths) == 2)
        #expect(ColumnDragController.insertionIndex(dragX: 350, offsets: offsets, widths: widths) == 3)
    }

    @Test func emptyTableReturnsZero() {
        #expect(ColumnDragController.insertionIndex(dragX: 100, offsets: [], widths: []) == 0)
    }

    // MARK: - reorder

    private let order = ["_title", "a", "b", "c"]

    @Test func moveForwardCompensatesRemovalShift() {
        // Move "a" (index 1) to insertion 3 (between b and c in original space)
        // → after removal it lands before "c".
        #expect(ColumnDragController.reorder(order, from: 1, to: 3) == ["_title", "b", "a", "c"])
    }

    @Test func moveBackwardInsertsAtIndex() {
        // Move "c" (index 3) to insertion 1 (after _title).
        #expect(ColumnDragController.reorder(order, from: 3, to: 1) == ["_title", "c", "a", "b"])
    }

    @Test func moveToZeroPlacesFirst() {
        #expect(ColumnDragController.reorder(order, from: 2, to: 0) == ["b", "_title", "a", "c"])
    }

    @Test func moveToEndAppends() {
        #expect(ColumnDragController.reorder(order, from: 1, to: 4) == ["_title", "b", "c", "a"])
    }

    @Test func noOpMoveReturnsUnchanged() {
        // Insertion at the column's own slot (or the slot just after it) is a no-op.
        #expect(ColumnDragController.reorder(order, from: 1, to: 1) == order)
        #expect(ColumnDragController.reorder(order, from: 1, to: 2) == order)
    }

    @Test func outOfRangeFromReturnsUnchanged() {
        #expect(ColumnDragController.reorder(order, from: 9, to: 0) == order)
    }
}
