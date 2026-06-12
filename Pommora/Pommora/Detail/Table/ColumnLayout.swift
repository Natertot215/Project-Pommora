import Foundation
import Observation

/// Live geometry store for the custom table's columns — the mutable source of
/// truth for column widths, order, and derived x-offsets used by rendering,
/// hit-testing, and resize-drag math.
///
/// Initialized from a resolved `[ResolvedColumn]`; column order is fixed at
/// init, widths are mutable via `setWidth`. Kept focused — just the live
/// geometry, no resolution logic (that's `TableColumnResolver`).
@MainActor @Observable final class ColumnLayout {
    /// Column descriptors in render order. Widths here are the live values;
    /// the resolved column's own `width` is the initial seed.
    private(set) var columns: [ResolvedColumn]

    /// Live width per column, in render order. Separate from `columns[i].width`
    /// (which is immutable) so resize mutates a single array.
    private(set) var widths: [Double]

    init(columns: [ResolvedColumn]) {
        self.columns = columns
        self.widths = columns.map(\.width)
    }

    /// Sum of all live column widths — the table's content width.
    var totalWidth: Double { widths.reduce(0, +) }

    /// X-offset (left edge) of the column at `index` — the prefix sum of every
    /// preceding column's width. `xOffset(at: 0)` is always 0; an out-of-range
    /// index past the end returns `totalWidth` (the right edge).
    func xOffset(at index: Int) -> Double {
        guard index > 0 else { return 0 }
        let upper = min(index, widths.count)
        return widths[0..<upper].reduce(0, +)
    }

    /// Updates the live width of the column at `index`, clamped to the 60pt
    /// minimum (parity with `TableColumnResolver`'s resolve-time clamp).
    func setWidth(_ width: Double, forColumnAt index: Int) {
        guard widths.indices.contains(index) else { return }
        widths[index] = max(60, width)
    }

    /// Left-edge x-offset of every column, in render order — the prefix sums the
    /// header drag-reorder math (`ColumnDragController.insertionIndex`) consumes
    /// to map a drag location onto a target insertion index.
    var offsets: [Double] {
        var running = 0.0
        return widths.map { width in
            defer { running += width }
            return running
        }
    }
}
