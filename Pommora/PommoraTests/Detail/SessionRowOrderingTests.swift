import Foundation
import Testing

@testable import Pommora

/// Tests for `SessionRowOrdering` — the pure-function helper that drives
/// session-local detail-pane drag-reorder. Session-only because the sidebar
/// owns persistent `order:` writes; this stays independent so v0.5.0 saved
/// view configs can migrate cleanly.
@Suite("SessionRowOrderingTests")
struct SessionRowOrderingTests {

    @Test("applySessionReorder() moves a row to a new index within the manager order")
    func sessionReorderMovesRow() {
        let baseIDs = ["a", "b", "c", "d"]
        // Move "a" (index 0) onto "c" (index 2): expected result [b, c, a, d]
        let reordered = SessionRowOrdering.apply(
            base: baseIDs,
            movingID: "a",
            ontoID: "c"
        )
        #expect(reordered == ["b", "c", "a", "d"])
    }

    @Test("applySessionReorder() is a no-op when source == target")
    func sessionReorderNoopSelfDrop() {
        let baseIDs = ["a", "b", "c"]
        let reordered = SessionRowOrdering.apply(
            base: baseIDs,
            movingID: "b",
            ontoID: "b"
        )
        #expect(reordered == baseIDs)
    }

    @Test("applySessionReorder() returns base when movingID not present")
    func sessionReorderUnknownIDReturnsBase() {
        let baseIDs = ["a", "b", "c"]
        let reordered = SessionRowOrdering.apply(
            base: baseIDs,
            movingID: "x",
            ontoID: "b"
        )
        #expect(reordered == baseIDs)
    }
}
