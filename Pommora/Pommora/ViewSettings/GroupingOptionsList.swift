import SwiftUI

/// Read-only (no Add) option list for the Grouping pane.
///
/// Reuses the `SelectOptionsEditor` / `StatusGroupsEditor` visual language
/// (chip + `≡` drag handle per row) without the Add affordance. Drag-reorder
/// is active only when `isDraggable == true` (Manual order mode); in other
/// modes the handle renders muted-quaternary and drag events are not wired.
///
/// `onReorder` receives the new ordered array of option IDs whenever a drag
/// completes. The caller (`OptionsSection`) translates this into a
/// `model.update { $0.order = newOrder }` write.
struct GroupingOptionsList: View {
    let chips: [PropertyChipOption]
    let isDraggable: Bool
    let onReorder: ([String]) -> Void

    var body: some View {
        VStack(spacing: PUI.Spacing.sm) {
            ForEach(chips) { chip in
                GroupingOptionsRow(
                    chip: chip,
                    isDraggable: isDraggable,
                    onDrop: isDraggable
                        ? { droppedIDs in handleDrop(droppedIDs, onto: chip.id) }
                        : { _ in false }
                )
            }
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Spacing.md)
    }

    private func handleDrop(_ droppedIDs: [String], onto targetID: String) -> Bool {
        guard let droppedID = droppedIDs.first, droppedID != targetID else { return false }
        var ids = chips.map(\.id)
        guard let srcIdx = ids.firstIndex(of: droppedID),
              let dstIdx = ids.firstIndex(of: targetID)
        else { return false }
        ids.remove(at: srcIdx)
        let adjusted = srcIdx < dstIdx ? dstIdx - 1 : dstIdx
        ids.insert(droppedID, at: min(max(adjusted, 0), ids.count))
        onReorder(ids)
        return true
    }
}

private struct GroupingOptionsRow: View {
    let chip: PropertyChipOption
    let isDraggable: Bool
    let onDrop: ([String]) -> Bool

    @State private var isDropTargeted: Bool = false

    var body: some View {
        HStack(spacing: PUI.Row.interSpacing) {
            PropertyChip(label: chip.label, color: chip.color)
            Spacer(minLength: 0)
            gripHandle
        }
        .contentShape(Rectangle())
        .if(isDraggable) { view in
            view
                .draggable(chip.id)
                .dropDestination(for: String.self) { droppedIDs, _ in
                    onDrop(droppedIDs)
                } isTargeted: {
                    isDropTargeted = $0
                }
                .optionRowInsertionLine(isActive: isDropTargeted)
        }
    }

    @ViewBuilder
    private var gripHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(PUI.Typography.chip)
            .foregroundStyle(isDraggable ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
            .help(isDraggable ? "Drag to reorder" : "Switch to Manual order to reorder")
    }
}

// MARK: - View+if helper

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
