import SwiftUI

/// One row in the Views dropdown: the view's icon + name on the LEFT, a chevron
/// opening the type submenu on the RIGHT. The active view carries a filled
/// highlight. Left-click switches to the view; right-click exposes Rename /
/// Edit Icon / Duplicate / Delete (Edit Icon is an inline menu, not a sheet).
///
/// Rendering is isolated into plain-value sub-properties (no GRDB-polluted
/// expressions in the @ViewBuilder body — quirk 12).
struct ViewsPanelRow: View {
    let view: SavedView
    let isActive: Bool
    let onSelect: () -> Void
    let onSwitchType: (ViewType) -> Void
    let onPickIcon: (String) -> Void
    let onRename: (String) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let canDelete: Bool

    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    /// Curated icons offered by the inline "Edit Icon" menu (friendly name +
    /// glyph) — a menu, not the full-screen picker sheet.
    private static let iconChoices: [(name: String, symbol: String)] = [
        ("Grid", "rectangle.grid.2x2"), ("Table", "tablecells"),
        ("Cells", "square.grid.3x3"), ("List", "list.bullet"),
        ("Columns", "rectangle.split.3x1"), ("Document", "doc"),
        ("Folder", "folder"), ("Tag", "tag"), ("Star", "star"),
        ("Flag", "flag"), ("Calendar", "calendar"), ("Photo", "photo"),
    ]

    var body: some View {
        HStack(spacing: PUI.Row.interSpacing) {
            Image(systemName: view.icon ?? view.type.defaultIcon)
                .font(PUI.Icon.leading)
                .foregroundStyle(.secondary)
                .frame(width: PUI.Icon.leadingFrame)

            nameLabel

            Spacer(minLength: 8)

            typeMenu
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
        }
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture { if !isEditingName { onSelect() } }
        .contextMenu {
            Button("Rename") { beginEditing() }
            Menu("Edit Icon") {
                ForEach(Self.iconChoices, id: \.symbol) { choice in
                    Button { onPickIcon(choice.symbol) } label: {
                        Label(choice.name, systemImage: choice.symbol)
                    }
                }
            }
            Button("Duplicate", action: onDuplicate)
            Button("Delete", role: .destructive, action: onDelete)
                .disabled(!canDelete)
        }
    }

    /// Right-aligned chevron that opens the view-type submenu (icon + text per
    /// implemented renderer; unimplemented types shown disabled).
    private var typeMenu: some View {
        Menu {
            ForEach(ViewType.allCases, id: \.self) { type in
                Button { onSwitchType(type) } label: {
                    Label(type.displayName, systemImage: type.defaultIcon)
                }
                .disabled(!type.isImplemented)
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(PUI.Icon.chevron)
                .foregroundStyle(.secondary)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
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
