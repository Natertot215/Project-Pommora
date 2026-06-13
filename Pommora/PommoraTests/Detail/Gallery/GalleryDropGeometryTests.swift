import CoreGraphics
import Testing

@testable import Pommora

/// Covers `GalleryDropGeometry`'s pure grid hit-test + insertion math.
/// `insertionIndex` maps a drop session's global location onto an insertion
/// index within a group's ordered cards via the nearest card's HORIZONTAL
/// midpoint (leading half → before, trailing half → after); past the last card
/// appends. No disk, no UI.
@Suite("GalleryDropGeometryTests") struct GalleryDropGeometryTests {

    // A 2-row grid of 100x100 cards, 3 per row, 10pt gaps:
    // Row 0 (y 0..100):   a[0..100] b[110..210] c[220..320]
    // Row 1 (y 110..210): d[0..100] e[110..210] f[220..320]
    // Card x-midpoints: 50, 160, 270.
    private func card(_ id: String, x: CGFloat, y: CGFloat, index: Int) -> GalleryDropGeometry.CardFrame {
        GalleryDropGeometry.CardFrame(
            id: id, frame: CGRect(x: x, y: y, width: 100, height: 100), indexInGroup: index)
    }

    private var cards: [GalleryDropGeometry.CardFrame] {
        [
            card("a", x: 0, y: 0, index: 0), card("b", x: 110, y: 0, index: 1),
            card("c", x: 220, y: 0, index: 2), card("d", x: 0, y: 110, index: 3),
            card("e", x: 110, y: 110, index: 4), card("f", x: 220, y: 110, index: 5),
        ]
    }

    @Test func leadingHalfTargetsThatCard() {
        #expect(GalleryDropGeometry.insertionIndex(location: CGPoint(x: 20, y: 50), cards: cards) == 0)
        #expect(GalleryDropGeometry.insertionIndex(location: CGPoint(x: 130, y: 50), cards: cards) == 1)
        #expect(GalleryDropGeometry.insertionIndex(location: CGPoint(x: 240, y: 50), cards: cards) == 2)
    }

    @Test func trailingHalfTargetsNextCard() {
        #expect(GalleryDropGeometry.insertionIndex(location: CGPoint(x: 80, y: 50), cards: cards) == 1)
        #expect(GalleryDropGeometry.insertionIndex(location: CGPoint(x: 190, y: 50), cards: cards) == 2)
        #expect(GalleryDropGeometry.insertionIndex(location: CGPoint(x: 300, y: 50), cards: cards) == 3)
    }

    @Test func secondRowFlowsAfterFirst() {
        // Leading half of the first card in row 1 (d, index 3) → 3.
        #expect(GalleryDropGeometry.insertionIndex(location: CGPoint(x: 20, y: 160), cards: cards) == 3)
        // Trailing half of the last card → append at 6.
        #expect(GalleryDropGeometry.insertionIndex(location: CGPoint(x: 300, y: 160), cards: cards) == 6)
    }

    @Test func rowEndGapFallsToNextRow() {
        // Cursor in the right margin of row 0 (past card c) is nearest to c;
        // its trailing half → index 3 (start of next row in flow order).
        #expect(GalleryDropGeometry.insertionIndex(location: CGPoint(x: 360, y: 50), cards: cards) == 3)
    }

    @Test func gapBetweenCardsResolvesToNearest() {
        // The 10pt gap between a (x-mid 50) and b (x-mid 160) at x=105 is nearer
        // b's leading region; x=105 < b.midX(160) but also > a.midX(50). Nearest
        // card by center is b (|105-160|=55 < |105-50|=55? tie-break → first min).
        // a is at distance 55, b at 55 — `min(by:)` keeps the first (a); a's
        // trailing half → 1.
        #expect(GalleryDropGeometry.insertionIndex(location: CGPoint(x: 105, y: 50), cards: cards) == 1)
    }

    @Test func locationBeforeFirstCardInsertsAtZero() {
        #expect(GalleryDropGeometry.insertionIndex(location: CGPoint(x: -50, y: 50), cards: cards) == 0)
    }

    @Test func emptyCardsReturnsNil() {
        #expect(GalleryDropGeometry.insertionIndex(location: CGPoint(x: 10, y: 10), cards: []) == nil)
    }

    @Test func nonZeroBaseIndexIsPreserved() {
        let offset = [card("x", x: 0, y: 0, index: 5), card("y", x: 110, y: 0, index: 6)]
        #expect(GalleryDropGeometry.insertionIndex(location: CGPoint(x: 20, y: 50), cards: offset) == 5)
        #expect(GalleryDropGeometry.insertionIndex(location: CGPoint(x: 200, y: 50), cards: offset) == 7)
    }
}
