import Testing

@testable import Pommora

/// T3.3 — the pure promoted/overflow partition that structurally resolves the
/// legacy Item-Window double-render (Fix Log #10). The contract: `main` carries
/// the promoted ids in promoted order (real ids only), `overflow` carries the
/// remainder in `all`'s original order, and the two are ALWAYS disjoint — no id
/// can appear in both regions.
@Suite struct ItemWindowPartitionTests {
    @Test func promotedAndOverflowAreDisjoint() {
        let all = ["a", "b", "c", "d"]
        let (main, overflow) = ItemWindowRenderer.partition(all: all, promoted: ["c", "a"])
        #expect(main == ["c", "a"])  // promoted order
        #expect(overflow == ["b", "d"])  // remainder in original order
        #expect(Set(main).intersection(Set(overflow)).isEmpty)  // THE bug: never both
    }

    @Test func promotedNotInAllIgnored() {
        let (main, overflow) = ItemWindowRenderer.partition(all: ["a", "b"], promoted: ["a", "zzz"])
        #expect(main == ["a"])
        #expect(overflow == ["b"])
    }

    @Test func emptyPromotedAllOverflow() {
        let (main, overflow) = ItemWindowRenderer.partition(all: ["a", "b"], promoted: [])
        #expect(main.isEmpty)
        #expect(overflow == ["a", "b"])
    }
}
