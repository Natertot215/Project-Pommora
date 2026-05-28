import SwiftUI

/// Shared editor for a Select / Multi-Select property's options array.
///
/// **Row design:** each option renders as a `PropertyChip(label, color)` with
/// a trailing `line.3.horizontal` grip. The chip is the interactive surface:
///   - **Double-click or right-click** opens the inline `OptionEditPopover`
///     for renaming / recoloring / deleting (no navigation hop).
///   - **Drag the grip** reorders within the list via `.draggable` +
///     `.dropDestination`.
///
/// **Add affordance:** a small `+ Add` row sits beneath the last option
/// (secondary tint). When options are empty, the `+ Add` row is the only
/// content — no placeholder text.
struct SelectOptionsEditor: View {
    @Binding var options: [PropertyDefinition.SelectOption]
    let onAddOption: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xl) {
            HStack {
                Text("Options")
                    .font(PUI.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                Spacer()
                addButton
            }

            if !options.isEmpty {
                VStack(spacing: PUI.Spacing.sm) {
                    ForEach(options, id: \.id) { option in
                        SelectOptionsRow(
                            option: option,
                            onUpdateLabel: { newLabel in
                                update(value: option.value) { $0.label = newLabel }
                            },
                            onUpdateColor: { newColor in
                                update(value: option.value) { $0.color = newColor?.toSelectColor() }
                            },
                            onDelete: {
                                options.removeAll { $0.value == option.value }
                            }
                        )
                        .dropDestination(for: String.self) { droppedValues, _ in
                            handleDrop(of: droppedValues, onto: option.value)
                        }
                    }
                }
            }
        }
    }

    /// "Add" affordance on the Options header row, right-aligned to the
    /// content rail (matches the title field's trailing edge).
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

    /// In-place mutation of an option by value. Triggers the binding setter
    /// which the parent (EditPropertyPane) routes through
    /// `updateProperty(transform:)`.
    private func update(value: String, mutate: (inout PropertyDefinition.SelectOption) -> Void) {
        guard let idx = options.firstIndex(where: { $0.value == value }) else { return }
        var opt = options[idx]
        mutate(&opt)
        options[idx] = opt
    }

    /// Reorder by moving the dropped option to the position of the target.
    private func handleDrop(of droppedValues: [String], onto targetValue: String) -> Bool {
        guard let droppedValue = droppedValues.first, droppedValue != targetValue else { return false }
        var newOptions = options
        guard let srcIdx = newOptions.firstIndex(where: { $0.value == droppedValue }),
              let dstIdx = newOptions.firstIndex(where: { $0.value == targetValue })
        else { return false }
        let item = newOptions.remove(at: srcIdx)
        // Removing the source first shifts everything after it left by one, so
        // a downward move targets dstIdx - 1 to land on the target's slot.
        let adjusted = srcIdx < dstIdx ? dstIdx - 1 : dstIdx
        let clamped = min(max(adjusted, 0), newOptions.count)
        newOptions.insert(item, at: clamped)
        options = newOptions
        return true
    }
}

private struct SelectOptionsRow: View {
    let option: PropertyDefinition.SelectOption
    let onUpdateLabel: (String) -> Void
    let onUpdateColor: (PropertyChipColor?) -> Void
    let onDelete: () -> Void

    @State private var showingPopover: Bool = false

    var body: some View {
        HStack(spacing: PUI.Row.interSpacing) {
            PropertyChip(
                label: option.label,
                color: PropertyChipColor(selectColor: option.color)
            )
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
