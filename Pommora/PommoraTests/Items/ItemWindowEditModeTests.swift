import Testing

@testable import Pommora

/// T3.5 — the pure reorder helper backing the renderer's edit-mode drag handler.
/// The `editing`-flag view gating (drag handles + pin checklist only in edit mode;
/// `promoted_properties` never mutated in the live window) is structural and
/// build-verified, not unit-tested here.
@Suite struct ItemWindowEditModeTests {
    @Test func reorderPreservesDisplayAndOrder() {
        let promoted = [
            PromotedProperty(id: "p1", display: .thumbnail),
            PromotedProperty(id: "p2", display: nil),
            PromotedProperty(id: "p3", display: .banner),
        ]
        let out = ItemWindowRenderer.reorderPromoted(promoted, moving: "p1", onto: "p3")
        // mirrors PropertyIDReorder.move (downward → lands BEFORE the target)
        #expect(out.map(\.id) == ["p2", "p1", "p3"])
        // per-property display preserved across the splice
        #expect(out.first { $0.id == "p1" }?.display == .thumbnail)
        #expect(out.first { $0.id == "p3" }?.display == .banner)
    }

    @Test func reorderNoOpOnUnknown() {
        let promoted = [PromotedProperty(id: "p1", display: nil)]
        #expect(ItemWindowRenderer.reorderPromoted(promoted, moving: "zzz", onto: "p1").map(\.id) == ["p1"])
    }
}
