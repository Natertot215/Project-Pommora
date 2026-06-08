import Testing

@testable import Pommora

/// The pure reorder helper retained on `ItemWindowRenderer` for the zone rework.
/// `reorderPromoted` reorders the promoted list by ID while preserving each
/// `PromotedProperty`'s per-property `display`; it stays unit-testable without a
/// SwiftUI host (no production caller references it yet).
@Suite struct ItemWindowReorderTests {
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
