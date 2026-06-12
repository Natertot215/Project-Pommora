import SwiftUI

/// One row in the Views dropdown panel: the view's icon + name on the LEFT, a
/// muted type label on the RIGHT. The type label is its OWN button that toggles
/// an inline type-switch expansion (handled by the parent `ViewsPanel`).
///
/// Inline edits:
///   - **Name** — double-click swaps the label for a `TextField`; commit calls
///     `onRename`.
///   - **Icon** — clicking the icon raises the icon picker via `onPickIcon`.
///
/// Rendering is isolated into plain-value sub-properties (no GRDB-polluted
/// expressions in the @ViewBuilder body — quirk 12).
struct ViewsPanelRow: View {
    let view: SavedView
    let isActive: Bool
    let isTypeExpanded: Bool
    let onSelect: () -> Void
    let onToggleType: () -> Void
    let onPickIcon: () -> Void
    let onRename: (String) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let canDelete: Bool

    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        HStack(spacing: PUI.Row.interSpacing) {
            Button(action: onPickIcon) {
                Image(systemName: view.icon ?? view.type.defaultIcon)
                    .font(PUI.Icon.leading)
                    .foregroundStyle(.primary)
                    .frame(width: PUI.Icon.leadingFrame)
            }
            .buttonStyle(.plain)

            nameLabel

            Spacer(minLength: 8)

            Button(action: onToggleType) {
                Text(view.typeLabel)
                    .font(PUI.Typography.caption)
                    .foregroundStyle(isTypeExpanded ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            if isActive {
                Image(systemName: "checkmark")
                    .font(PUI.Icon.chevron)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)
        .contentShape(Rectangle())
        .onTapGesture { if !isEditingName { onSelect() } }
        .contextMenu {
            Button("Rename") { beginEditing() }
            Button("Duplicate", action: onDuplicate)
            Button("Delete", role: .destructive, action: onDelete)
                .disabled(!canDelete)
        }
    }

    @ViewBuilder
    private var nameLabel: some View {
        if isEditingName {
            TextField("Name", text: $draftName)
                .textFieldStyle(.plain)
                .font(PUI.Typography.row)
                .focused($nameFieldFocused)
                .onSubmit(commitName)
                .onChange(of: nameFieldFocused) { _, focused in
                    if !focused { commitName() }
                }
        } else {
            Text(view.name)
                .font(PUI.Typography.row)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .onTapGesture(count: 2) { beginEditing() }
        }
    }

    private func beginEditing() {
        draftName = view.name
        isEditingName = true
        nameFieldFocused = true
    }

    private func commitName() {
        guard isEditingName else { return }
        isEditingName = false
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != view.name { onRename(trimmed) }
    }
}
