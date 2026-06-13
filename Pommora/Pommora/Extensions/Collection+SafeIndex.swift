import Foundation

extension Collection {
    /// Bounds-safe subscript — returns the element at `index` when in range, or
    /// `nil` instead of trapping. Lets renderers / pipeline code read a possibly-
    /// stale index (e.g. a drop marker against a just-recomputed group) without a
    /// guard at every call site.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
