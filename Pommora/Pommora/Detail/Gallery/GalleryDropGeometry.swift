import CoreGraphics

/// Pure grid hit-testing + insertion math for the gallery's card drag — the
/// grid-flow analogue of `RowDragGeometry`'s vertical-midpoint logic. Given the
/// live card frames in a shared coordinate space and the drop session's global
/// location, it resolves where in the flattened FLOW SEQUENCE a drop would land:
/// find the card the cursor is over (or nearest to), then split on its
/// HORIZONTAL midpoint — leading half inserts before the card, trailing half
/// after it. Past the last card appends.
///
/// Kept free of actor isolation + SwiftUI types (`Sendable`, value-only) so it
/// unit-tests without disk or UI; the drag wiring lives on `GalleryView`.
enum GalleryDropGeometry {

    /// A single hit-tested card: its stable id, its frame, and its index within
    /// the group's flattened `flattenedItems` flow order.
    struct CardFrame: Sendable, Equatable {
        let id: String
        let frame: CGRect
        let indexInGroup: Int
    }

    /// The insertion index a drop at `location` resolves to within one group's
    /// ordered `cards` (flow order). The index is in the group's flattened
    /// coordinate space — a drop in a card's leading half targets that card's
    /// index, the trailing half targets the next index; past the last card
    /// appends at `lastIndex + 1`. Returns nil when `cards` is empty.
    ///
    /// Grid flow: the cursor's nearest card is the one whose frame contains it,
    /// or — when over a gap / margin — the nearest by center distance. The
    /// leading/trailing split is the card's horizontal midpoint, so row-end gaps
    /// fall through to the next row's first card naturally (its leading half).
    ///
    /// `cards` must be in render flow order (ascending `indexInGroup`).
    static func insertionIndex(location: CGPoint, cards: [CardFrame]) -> Int? {
        guard let nearest = nearestCard(to: location, in: cards) else { return nil }
        if location.x < nearest.frame.midX { return nearest.indexInGroup }
        return nearest.indexInGroup + 1
    }

    /// The card the location sits inside, else the card whose center is closest.
    private static func nearestCard(to location: CGPoint, in cards: [CardFrame]) -> CardFrame? {
        if let hit = cards.first(where: { $0.frame.contains(location) }) { return hit }
        return cards.min(by: { distanceSquared(location, $0.frame) < distanceSquared(location, $1.frame) })
    }

    private static func distanceSquared(_ point: CGPoint, _ frame: CGRect) -> CGFloat {
        let dx = point.x - frame.midX
        let dy = point.y - frame.midY
        return dx * dx + dy * dy
    }
}
