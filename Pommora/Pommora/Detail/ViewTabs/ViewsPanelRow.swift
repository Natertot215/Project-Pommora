import SwiftUI

/// One row in the Views dropdown: display icon + name on the LEFT, a chevron
/// opening the view-type picker (flies RIGHT) on the RIGHT. The active view
/// carries a filled highlight. Left-click switches to the view; right-click →
/// Rename / Edit Icon (our `IconPicker`, flies LEFT) / Duplicate / Delete.
///
/// Rendering is isolated into plain-value sub-properties (no GRDB-polluted
/// expressions in the @ViewBuilder body — quirk 12).
struct ViewsPanelRow: View {
    let view: SavedView
    let isActive: Bool
    let onSelect: () -> Void
    let onSwitchType: (ViewType) -> Void
    let onPickIcon: (String?) -> Void
    let onRename: (String) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let canDelete: Bool

    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool
    @State private var showTypePicker = false
    @State private var showIconPicker = false

    var body: some View {
        HStack(spacing: PUI.Row.interSpacing) {
            Image(systemName: view.icon ?? view.type.defaultIcon)
                .font(PUI.Icon.leading)
                .foregroundStyle(.secondary)
                .frame(width: PUI.Icon.leadingFrame)

            nameLabel

            Spacer(minLength: 8)

            chevron
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)
        .contentShape(Rectangle())
        .onTapGesture { if !isEditingName { onSelect() } }
        .contextMenu {
            Button("Rename") { beginEditing() }
            Button("Edit Icon") { showIconPicker = true }
            Button("Duplicate", action: onDuplicate)
            Button("Delete", role: .destructive, action: onDelete)
                .disabled(!canDelete)
        }
        .popover(isPresented: $showIconPicker, arrowEdge: .leading) {
            IconPicker(symbol: iconBinding)
                .presentationBackground(.clear)
        }
    }

    /// Chevron that opens the view-type picker, flown to the RIGHT of the row.
    private var chevron: some View {
        Button { showTypePicker = true } label: {
            Image(systemName: "chevron.right")
                .font(PUI.Icon.chevron)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showTypePicker, arrowEdge: .trailing) {
            typePicker
                .presentationBackground(.clear)
        }
    }

    /// Compact panel of the implemented renderer types (current one check-marked).
    private var typePicker: some View {
        VStack(spacing: 0) {
            ForEach(ViewType.allCases.filter(\.isImplemented), id: \.self) { type in
                Button {
                    onSwitchType(type)
                    showTypePicker = false
                } label: {
                    HStack(spacing: PUI.Row.interSpacing) {
                        Image(systemName: type.defaultIcon)
                            .font(PUI.Icon.leading)
                            .frame(width: PUI.Icon.leadingFrame)
                        Text(type.displayName)
                            .font(PUI.Typography.row)
                        Spacer(minLength: 12)
                        if type == view.type {
                            Image(systemName: "checkmark")
                                .font(PUI.Icon.chevron)
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(.horizontal, PUI.Row.paddingHorizontal)
                    .padding(.vertical, PUI.Row.paddingVertical)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, PUI.Spacing.sm)
        .frame(width: 180)
        .chipDropdownPanel()
    }

    /// Bridges `view.icon` to the `IconPicker`'s nullable symbol binding (nil =
    /// Remove Icon).
    private var iconBinding: Binding<String?> {
        Binding(get: { view.icon }, set: { onPickIcon($0) })
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
