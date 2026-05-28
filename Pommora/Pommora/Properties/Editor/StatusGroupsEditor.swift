import SwiftUI

/// Shared editor for a Status property's 3 fixed groups + their options.
///
/// **Row design:** each option renders as a `PropertyChip(label, color)` with
/// a trailing `line.3.horizontal` grip. The chip is the interactive surface:
///   - **Double-click or right-click** opens the inline `OptionEditPopover`
///     for renaming / recoloring / deleting.
///   - **Drag the grip** reorders within the same group OR moves across
///     groups. Cross-group drops stage a confirmation dialog and apply on
///     confirm; intra-group drops apply immediately.
///
/// Option color falls back to the group's `color` when `option.color` is
/// nil — the chip preview shows the group default tone.
///
/// **Per-group `+ Add` row** sits beneath the last option in each group
/// (or as the only row when the group is empty).
///
/// The 3 group IDs (`upcoming` / `inProgress` / `done`) are fixed — only
/// group labels are renameable.
struct StatusGroupsEditor: View {
    @Binding var groups: [PropertyDefinition.StatusGroup]
    let onAddOption: (PropertyDefinition.StatusGroupID) -> Void

    @State private var pendingCrossGroupMove: PendingMove?

    fileprivate struct PendingMove: Identifiable, Equatable {
        let id = UUID()
        let optionValue: String
        let optionLabel: String
        let fromGroupID: PropertyDefinition.StatusGroupID
        let toGroupID: PropertyDefinition.StatusGroupID
        let toGroupLabel: String
        let insertAtIndex: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xl) {
            ForEach($groups) { $group in
                StatusGroupSection(
                    group: $group,
                    onAddOption: { onAddOption(group.id) },
                    onUpdateOption: { value, mutate in
                        updateOption(groupID: group.id, value: value, mutate: mutate)
                    },
                    onDeleteOption: { value in
                        deleteOption(groupID: group.id, value: value)
                    },
                    onDropOption: { droppedValue, insertAtIndex in
                        handleDrop(
                            droppedValue: droppedValue,
                            targetGroupID: group.id,
                            insertAtIndex: insertAtIndex
                        )
                    }
                )
            }
        }
        .confirmationDialog(
            confirmTitle,
            isPresented: pendingMoveBinding,
            titleVisibility: .visible,
            presenting: pendingCrossGroupMove
        ) { move in
            Button("Move", role: .destructive) {
                applyMove(move)
                pendingCrossGroupMove = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCrossGroupMove = nil
            }
        } message: { _ in
            Text("Entities currently using this option will be re-grouped. Affected-entity count surfaces in a future v0.3.1.x patch.")
        }
    }

    // MARK: - Option mutation (inline)

    private func updateOption(
        groupID: PropertyDefinition.StatusGroupID,
        value: String,
        mutate: (inout PropertyDefinition.StatusOption) -> Void
    ) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }),
              let oi = groups[gi].options.firstIndex(where: { $0.value == value })
        else { return }
        var opt = groups[gi].options[oi]
        mutate(&opt)
        groups[gi].options[oi] = opt
    }

    private func deleteOption(
        groupID: PropertyDefinition.StatusGroupID,
        value: String
    ) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[gi].options.removeAll { $0.value == value }
    }

    // MARK: - Drag-reorder handling

    private func handleDrop(
        droppedValue: String,
        targetGroupID: PropertyDefinition.StatusGroupID,
        insertAtIndex: Int
    ) -> Bool {
        var sourceGroupID: PropertyDefinition.StatusGroupID?
        var sourceOption: PropertyDefinition.StatusOption?
        var sourceIdx: Int?
        for g in groups {
            if let idx = g.options.firstIndex(where: { $0.value == droppedValue }) {
                sourceGroupID = g.id
                sourceOption = g.options[idx]
                sourceIdx = idx
                break
            }
        }
        guard let fromID = sourceGroupID,
              let opt = sourceOption,
              let srcIdx = sourceIdx
        else { return false }

        if fromID == targetGroupID {
            applyIntraGroupMove(groupID: fromID, from: srcIdx, to: insertAtIndex)
            return true
        }

        let toGroup = groups.first(where: { $0.id == targetGroupID })
        pendingCrossGroupMove = PendingMove(
            optionValue: opt.value,
            optionLabel: opt.label,
            fromGroupID: fromID,
            toGroupID: targetGroupID,
            toGroupLabel: toGroup?.label ?? targetGroupID.rawValue,
            insertAtIndex: insertAtIndex
        )
        return true
    }

    private func applyIntraGroupMove(
        groupID: PropertyDefinition.StatusGroupID,
        from srcIdx: Int,
        to dstIdx: Int
    ) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }) else { return }
        var opts = groups[gi].options
        guard srcIdx >= 0, srcIdx < opts.count else { return }
        let opt = opts.remove(at: srcIdx)
        // Removing the source first shifts everything after it left by one, so
        // a downward move targets dstIdx - 1 to land on the target's slot.
        let adjusted = srcIdx < dstIdx ? dstIdx - 1 : dstIdx
        let clamped = min(max(adjusted, 0), opts.count)
        opts.insert(opt, at: clamped)
        groups[gi].options = opts
    }

    private func applyMove(_ move: PendingMove) {
        var newGroups = groups
        guard let srcGi = newGroups.firstIndex(where: { $0.id == move.fromGroupID }),
              let srcOi = newGroups[srcGi].options.firstIndex(where: { $0.value == move.optionValue })
        else { return }
        var opt = newGroups[srcGi].options.remove(at: srcOi)
        opt.groupID = move.toGroupID
        guard let dstGi = newGroups.firstIndex(where: { $0.id == move.toGroupID }) else { return }
        let clamped = min(max(move.insertAtIndex, 0), newGroups[dstGi].options.count)
        newGroups[dstGi].options.insert(opt, at: clamped)
        groups = newGroups
    }

    private var pendingMoveBinding: Binding<Bool> {
        Binding(
            get: { pendingCrossGroupMove != nil },
            set: { isPresented in
                if !isPresented { pendingCrossGroupMove = nil }
            }
        )
    }

    private var confirmTitle: String {
        guard let move = pendingCrossGroupMove else { return "" }
        return "Move “\(move.optionLabel)” to \(move.toGroupLabel)?"
    }
}

private struct StatusGroupSection: View {
    @Binding var group: PropertyDefinition.StatusGroup
    let onAddOption: () -> Void
    let onUpdateOption: (String, (inout PropertyDefinition.StatusOption) -> Void) -> Void
    let onDeleteOption: (String) -> Void
    let onDropOption: (_ droppedValue: String, _ insertAtIndex: Int) -> Bool

    @FocusState private var labelFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xl) {
            HStack(spacing: PUI.Spacing.md) {
                // Group label is renameable inline. `.fixedSize` constrains the
                // caret/click target to just the label text (not the whole row
                // width). Enter / click-outside both clear focus + commit.
                TextField("Group label", text: $group.label)
                    .textFieldStyle(.plain)
                    .font(PUI.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .focused($labelFocused)
                    .onSubmit { labelFocused = false }
                Spacer()
                addButton
            }

            if !group.options.isEmpty {
                VStack(spacing: PUI.Spacing.sm) {
                    ForEach(Array(group.options.enumerated()), id: \.element.id) { idx, option in
                        StatusOptionRow(
                            option: option,
                            groupColor: group.color,
                            onUpdateLabel: { newLabel in
                                onUpdateOption(option.value) { $0.label = newLabel }
                            },
                            onUpdateColor: { newColor in
                                onUpdateOption(option.value) {
                                    $0.color = newColor?.toSelectColor()
                                }
                            },
                            onDelete: { onDeleteOption(option.value) }
                        )
                        .dropDestination(for: String.self) { droppedValues, _ in
                            guard let v = droppedValues.first else { return false }
                            return onDropOption(v, idx)
                        }
                    }
                }
                // +6pt below the final chip so each group reads as distinct.
                .padding(.bottom, PUI.Spacing.sm)
            }
        }
        // Drops on the section's empty area (header padding, gaps) route
        // to "append at end of this group's options."
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { droppedValues, _ in
            guard let v = droppedValues.first else { return false }
            return onDropOption(v, group.options.count)
        }
    }

    /// Per-group "Add" affordance on the group header row, right-aligned.
    @ViewBuilder
    private var addButton: some View {
        Button(action: onAddOption) {
            Text("Add")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}

private struct StatusOptionRow: View {
    let option: PropertyDefinition.StatusOption
    let groupColor: PropertyDefinition.SelectColor
    let onUpdateLabel: (String) -> Void
    let onUpdateColor: (PropertyChipColor?) -> Void
    let onDelete: () -> Void

    @State private var showingPopover: Bool = false

    private var chipColor: PropertyChipColor {
        // Option color overrides; nil inherits group default.
        PropertyChipColor(selectColor: option.color ?? groupColor)
    }

    var body: some View {
        HStack(spacing: PUI.Row.interSpacing) {
            PropertyChip(label: option.label, color: chipColor)
                .popover(isPresented: $showingPopover, arrowEdge: .leading) {
                    OptionEditPopover(
                        label: option.label,
                        color: PropertyChipColor(selectColor: option.color),
                        onCommitLabel: onUpdateLabel,
                        onCommitColor: onUpdateColor,
                        onDelete: onDelete
                    )
                }
            Spacer()
            // Triple-line grip = the drag handle (sized to chip text).
            Image(systemName: "line.3.horizontal")
                .font(PUI.Typography.chip)
                .foregroundStyle(.secondary)
                .draggable(option.value)
                .help("Drag to reorder")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            showingPopover = true
        }
        .onSecondaryClick {
            showingPopover = true
        }
    }
}
