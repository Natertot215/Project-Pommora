import Foundation

enum PropertyIDReorder {
    /// Moves `moving` to `target`'s slot in an ID array. Mirrors PropertyVisibilityPane's
    /// shift-adjusted splice exactly (downward move targets dstIdx-1 after removal).
    static func move(_ order: [String], moving: String, onto target: String) -> [String] {
        guard moving != target,
            let src = order.firstIndex(of: moving),
            let dst = order.firstIndex(of: target)
        else { return order }
        var out = order
        let item = out.remove(at: src)
        let adjusted = src < dst ? dst - 1 : dst
        out.insert(item, at: min(max(adjusted, 0), out.count))
        return out
    }
}
