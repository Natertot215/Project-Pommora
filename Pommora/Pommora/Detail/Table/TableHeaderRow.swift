import SwiftUI

/// The custom table's pinned column-header row. Mounted via `.safeAreaInset`
/// on the inner vertical scroll view (see `CustomTableView`) so it stays fixed
/// vertically while panning horizontally with the body in column alignment.
///
/// Each header cell = the `ResolvedColumn`'s icon + title, fixed to the live
/// column width (`ColumnLayout.widths`). Task 10 adds three interactions on the
/// header: a trailing resize handle (persisted on end), a press-drag reorder
/// (floating preview + persisted order), and a "Hide Column" context menu.
///
/// All persistence routes through closures the detail view supplies — the
/// header never touches a manager (parity with `CustomTableView`'s closure
/// inputs). `colID` (the `ResolvedColumn.id`) is the persistence key.
struct TableHeaderRow: View {
    let columns: [ResolvedColumn]
    let layout: ColumnLayout
    let rowHeight: CGFloat

    /// Persist a column's final width after a resize gesture ends.
    let persistWidth: (_ colID: String, _ width: Double) -> Void
    /// Persist a reordered `propertyOrder` after a drag-reorder drops.
    let persistOrder: (_ newOrder: [String]) -> Void
    /// Append a column to `hiddenProperties` (the menu disables `_title`).
    let hideColumn: (_ colID: String) -> Void

    /// The live header-drag state — modeled as an enum so the body switches over
    /// a finite set of modes rather than juggling loose optionals (HARD RULE:
    /// condensed exhaustive control flow). `.idle` = no interaction; `.resizing`
    /// snapshots the start width; `.reordering` tracks the dragged column index +
    /// the current content-x for the floating preview + insertion math.
    enum DragState: Equatable {
        case idle
        case resizing(index: Int, startWidth: Double)
        case reordering(index: Int, locationX: Double)
    }

    @State private var dragState: DragState = .idle

    /// Shared coordinate space so the reorder drag's x-location maps onto the
    /// column prefix sums (`layout.offsets`).
    private let space = "TableHeader"

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                HeaderCell(
                    column: column,
                    width: width(at: index),
                    rowHeight: rowHeight,
                    isDraggingThis: isReordering(index),
                    isTitle: column.id == ReservedPropertyID.title,
                    onResize: { resize(index: index, translationWidth: $0) },
                    onResizeEnd: { endResize(index: index) },
                    onReorder: { beginOrUpdateReorder(index: index, locationX: $0) },
                    onReorderEnd: { endReorder(index: index) },
                    onHide: { hideColumn(column.id) }
                )
            }
        }
        .frame(height: rowHeight)
        .background(.bar)
        .coordinateSpace(name: space)
        .overlay(alignment: .topLeading) { reorderPreview }
    }

    // MARK: - Floating reorder preview

    @ViewBuilder
    private var reorderPreview: some View {
        if case .reordering(let index, let locationX) = dragState, columns.indices.contains(index) {
            let w = width(at: index)
            HeaderCell(
                column: columns[index],
                width: w,
                rowHeight: rowHeight,
                isDraggingThis: false,
                isTitle: false,
                onResize: { _ in }, onResizeEnd: {},
                onReorder: { _ in }, onReorderEnd: {}, onHide: {}
            )
            .background(.bar)
            .opacity(0.9)
            .shadow(radius: 4)
            .offset(x: locationX - w / 2)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Resize

    private func resize(index: Int, translationWidth: CGFloat) {
        let start: Double
        if case .resizing(let i, let startWidth) = dragState, i == index {
            start = startWidth
        } else {
            start = layout.widths.indices.contains(index) ? layout.widths[index] : 0
            dragState = .resizing(index: index, startWidth: start)
        }
        layout.setWidth(start + Double(translationWidth), forColumnAt: index)
    }

    private func endResize(index: Int) {
        if layout.widths.indices.contains(index), columns.indices.contains(index) {
            persistWidth(columns[index].id, layout.widths[index])
        }
        dragState = .idle
    }

    // MARK: - Reorder

    private func beginOrUpdateReorder(index: Int, locationX: CGFloat) {
        dragState = .reordering(index: index, locationX: Double(locationX))
    }

    private func endReorder(index: Int) {
        guard case .reordering(_, let locationX) = dragState else {
            dragState = .idle
            return
        }
        let target = ColumnDragController.insertionIndex(
            dragX: locationX, offsets: layout.offsets, widths: layout.widths)
        let order = columns.map(\.id)
        let newOrder = ColumnDragController.reorder(order, from: index, to: target)
        dragState = .idle
        if newOrder != order { persistOrder(newOrder) }
    }

    // MARK: - Geometry

    private func isReordering(_ index: Int) -> Bool {
        if case .reordering(let i, _) = dragState { return i == index }
        return false
    }

    private func width(at index: Int) -> CGFloat {
        guard layout.widths.indices.contains(index) else {
            return CGFloat(columns[index].width)
        }
        return CGFloat(layout.widths[index])
    }
}

/// One header cell — isolated as a plain value-typed sub-view (quirk #12) so the
/// per-column rendering + its gestures stay out of the parent `@ViewBuilder`.
/// Owns the resize handle (trailing), the press-drag reorder gesture, and the
/// "Hide Column" context menu; reports back to `TableHeaderRow` via closures.
private struct HeaderCell: View {
    let column: ResolvedColumn
    let width: CGFloat
    let rowHeight: CGFloat
    let isDraggingThis: Bool
    let isTitle: Bool

    let onResize: (CGFloat) -> Void
    let onResizeEnd: () -> Void
    let onReorder: (CGFloat) -> Void
    let onReorderEnd: () -> Void
    let onHide: () -> Void

    /// Trailing resize-handle hit width (points).
    private static let handleWidth: CGFloat = 5

    var body: some View {
        label
            .frame(width: width, height: rowHeight, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(isDraggingThis ? 0.3 : 1)
            .gesture(reorderGesture)
            .overlay(alignment: .trailing) { resizeHandle }
            .contextMenu {
                Button("Hide Column") { onHide() }
                    .disabled(isTitle)
            }
    }

    private var label: some View {
        // Plain text header — native NSTableColumn headers show no leading icon.
        HStack(spacing: 0) {
            Text(column.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PUI.Spacing.md)
    }

    /// Press-drag on the cell body (NOT the resize zone) reorders the column.
    /// Uses the shared "TableHeader" coordinate space so the x-location maps
    /// onto the column prefix sums.
    private var reorderGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("TableHeader"))
            .onChanged { value in onReorder(value.location.x) }
            .onEnded { _ in onReorderEnd() }
    }

    /// 5pt trailing hit area driving the live resize; clamped to 60pt inside
    /// `ColumnLayout.setWidth`. `pointerStyle(.columnResize)` shows the resize
    /// cursor on hover (macOS 15+).
    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: Self.handleWidth)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in onResize(value.translation.width) }
                    .onEnded { _ in onResizeEnd() }
            )
    }
}
