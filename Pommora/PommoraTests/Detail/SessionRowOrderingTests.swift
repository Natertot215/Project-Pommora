import Foundation
import Testing

@testable import Pommora

/// Tests for `SessionRowOrdering` — the pure-function helper that drives
/// session-local detail-pane drag-reorder. Session-only because the sidebar
/// owns persistent `order:` writes; this stays independent so v0.5.0 saved
/// view configs can migrate cleanly.
@Suite("SessionRowOrderingTests")
struct SessionRowOrderingTests {

    @Test("move() relocates a row to an earlier offset")
    func moveToEarlierOffset() {
        // [a,b,c,d], move "d" to offset 1 → [a, d, b, c]
        let reordered = SessionRowOrdering.move(base: ["a", "b", "c", "d"], movingID: "d", toOffset: 1)
        #expect(reordered == ["a", "d", "b", "c"])
    }

    @Test("move() relocates a row to a later offset (offset measured pre-removal)")
    func moveToLaterOffset() {
        // [a,b,c,d], move "a" to offset 3 → remove a → [b,c,d], insert at 2 → [b, c, a, d]
        let reordered = SessionRowOrdering.move(base: ["a", "b", "c", "d"], movingID: "a", toOffset: 3)
        #expect(reordered == ["b", "c", "a", "d"])
    }

    @Test("move() to the end-of-list offset appends")
    func moveToEnd() {
        // [a,b,c], move "a" to offset 3 (== count) → [b, c, a]
        let reordered = SessionRowOrdering.move(base: ["a", "b", "c"], movingID: "a", toOffset: 3)
        #expect(reordered == ["b", "c", "a"])
    }

    @Test("move() is a no-op when dropped onto its own slot")
    func moveNoopSelfDrop() {
        // Dropping "b" at its own index (1) or just after it (2) leaves order intact.
        #expect(SessionRowOrdering.move(base: ["a", "b", "c"], movingID: "b", toOffset: 1) == ["a", "b", "c"])
        #expect(SessionRowOrdering.move(base: ["a", "b", "c"], movingID: "b", toOffset: 2) == ["a", "b", "c"])
    }

    @Test("move() returns base when movingID not present")
    func moveUnknownIDReturnsBase() {
        let baseIDs = ["a", "b", "c"]
        let reordered = SessionRowOrdering.move(base: baseIDs, movingID: "x", toOffset: 1)
        #expect(reordered == baseIDs)
    }

    @Test("move() to offset 0 brings a later row to the front")
    func moveToFront() {
        // [a,b,c], move "c" to offset 0 ⇒ [c,a,b]
        let reordered = SessionRowOrdering.move(base: ["a", "b", "c"], movingID: "c", toOffset: 0)
        #expect(reordered == ["c", "a", "b"])
    }

    // MARK: - reconcile

    @Test("reconcile returns base unchanged when sessionOrder is nil")
    func reconcileNilPassesThrough() {
        let base = [Row("a"), Row("b")]
        #expect(SessionRowOrdering.reconcile(base: base, sessionOrder: nil) == base)
    }

    @Test("reconcile honors session order, then appends rows added since the reorder")
    func reconcileOrdersThenAppends() {
        // "c" was created after the user reordered to [b, a]; it appends at the end.
        let base = [Row("a"), Row("b"), Row("c")]
        let result = SessionRowOrdering.reconcile(base: base, sessionOrder: ["b", "a"])
        #expect(result == [Row("b"), Row("a"), Row("c")])
    }

    @Test("reconcile drops session IDs no longer present in base")
    func reconcileDropsStaleIDs() {
        // "ghost" was deleted since the reorder; it's silently dropped.
        let base = [Row("a"), Row("b")]
        let result = SessionRowOrdering.reconcile(base: base, sessionOrder: ["b", "ghost", "a"])
        #expect(result == [Row("b"), Row("a")])
    }
}

/// Minimal `Identifiable` fixture for `reconcile` tests.
private struct Row: Identifiable, Equatable {
    let id: String
    init(_ id: String) { self.id = id }
}
