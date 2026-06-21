import SwiftUI

/// A renderable option for `ChipDropdown` — id + label + chip color.
struct PropertyChipOption: Identifiable, Hashable {
    let id: String
    let label: String
    let color: PropertyChipColor
}

enum SelectionMode { case single, multi }

/// Liquid-Glass chip dropdown pulled from the Component Library. The pill is
/// the trigger (hosted by the caller's `.popover`); this is the panel.
/// `.single` picks one; `.multi` toggles + drag-reorders the options binding.
/// `size` scales the chips/checkboxes for the host context.
struct ChipDropdown: View {
    @Binding var options: [PropertyChipOption]
    let selectionMode: SelectionMode
    let selectedIDs: Set<String>
    let onPick: (PropertyChipOption) -> Void
    var size: PropertyChip.Size = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
            ForEach(options) { opt in rowView(for: opt) }
        }
        .padding(PUI.Spacing.md)
        // Shared Liquid Glass panel surface (material fill + hairline + clip) —
        // always-on so the panel reads the same in any host context.
        .chipDropdownPanel()
        // Content-driven sizing — collapses to the natural VStack width.
        .fixedSize(horizontal: true, vertical: true)
    }

    @ViewBuilder
    private func rowView(for opt: PropertyChipOption) -> some View {
        let row = ChipDropdownRow(
            option: opt,
            isSelected: selectedIDs.contains(opt.id),
            showCheckbox: selectionMode == .multi,
            size: size,
            onPick: { onPick(opt) }
        )
        switch selectionMode {
        case .single:
            row
        case .multi:
            // Drag-reorder via Transferable on the option's id (String).
            // Multi-select only — single-select rows have nothing to reorder.
            row
                .draggable(opt.id)
                .dropDestination(for: String.self) { droppedIDs, _ in
                    handleDrop(droppedIDs, ontoID: opt.id)
                }
        }
    }

    private func handleDrop(_ droppedIDs: [String], ontoID targetID: String) -> Bool {
        guard let droppedID = droppedIDs.first,
              droppedID != targetID,
              let srcIdx = options.firstIndex(where: { $0.id == droppedID }),
              let dstIdx = options.firstIndex(where: { $0.id == targetID })
        else { return false }
        let item = options.remove(at: srcIdx)
        // Removing the source first shifts everything after it left by one, so
        // a downward move targets dstIdx - 1 to land on the target's slot.
        let insertAt = srcIdx < dstIdx ? dstIdx - 1 : dstIdx
        options.insert(item, at: insertAt)
        return true
    }
}

private struct ChipDropdownRow: View {
    let option: PropertyChipOption
    let isSelected: Bool
    let showCheckbox: Bool
    var size: PropertyChip.Size = .standard
    let onPick: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: PUI.Spacing.sm) {
            if showCheckbox {
                PropertyCheckbox(
                    isChecked: Binding(get: { isSelected }, set: { _ in onPick() }),
                    color: .blue,
                    icon: "checkmark",
                    size: size == .standard ? 16 : 13
                )
            }
            Button(action: onPick) {
                HStack(spacing: PUI.Spacing.xs) {
                    PropertyChip(label: option.label, color: option.color, size: size)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, PUI.Spacing.xs)
        .padding(.vertical, PUI.Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: PUI.Radius.card)
                .fill(isHovered ? Color(.textBackgroundColor).opacity(0.2) : .clear)
        )
        .onHover { isHovered = $0 }
    }
}
