import SwiftUI

/// Shared detail title-with-icon header: a static title shown beside (or above)
/// an SF Symbol icon that, on right-click, offers "Rename" (inline `TextField`,
/// commit on Enter / focus-loss, Esc cancels) and "Change Icon" (anchored
/// `iconPickerPopover`). Folds the near-identical interaction that lived in the
/// context detail placeholder and the storage-view header.
///
/// Layout-neutral: the caller picks the `axis` (icon beside vs. above the title)
/// plus alignment/color knobs, then wraps this in its own container padding so
/// each surface keeps its exact layout. The interaction (context menu + picker
/// popover) attaches to the whole icon+title group as one unit.
///
/// `onIconChange == nil` drops the "Change Icon" item; with both `onRename` and
/// `onIconChange` nil the header is display-only (no context menu / popover).
struct DetailTitleHeader: View {
    let title: String
    /// SF Symbol name; empty hides the icon entirely.
    let icon: String
    var titleFont: Font = .title.bold()
    var iconFont: Font = .title.bold()
    /// Icon tint; `nil` falls back to `.primary`.
    var iconColor: Color? = nil
    /// Icon vs. title arrangement — `.horizontal` (beside) or `.vertical` (above).
    var axis: Axis = .horizontal
    /// Cross-axis alignment of the vertical stack + title text alignment. Default
    /// suits a leading header; the centered placeholder passes `.center`.
    var horizontalAlignment: HorizontalAlignment = .leading
    var textAlignment: TextAlignment = .leading
    var spacing: CGFloat = PUI.Spacing.sm
    /// Caps the rename field's width — the centered placeholder constrains it to
    /// keep the field from spanning the whole pane; `nil` leaves it uncapped.
    var fieldMaxWidth: CGFloat? = nil
    /// `.plain` text-field style on the rename field (headers use it; the
    /// centered placeholder keeps the default field chrome).
    var plainField: Bool = false

    /// Renames the entity to the committed (trimmed, changed, non-empty) title.
    var onRename: ((String) async -> Void)? = nil
    /// Persists a picked (or cleared) icon. `nil` drops the "Change Icon" item.
    var onIconChange: ((String?) async -> Void)? = nil
    /// Fired the moment rename mode exits on commit (Enter or focus-loss), before
    /// `onRename` — a hook for handing first responder elsewhere on commit.
    var onCommitted: (() -> Void)? = nil

    @State private var isRenaming = false
    @State private var draft = ""
    @State private var pickerOpen = false
    @FocusState private var focused: Bool

    private var interactive: Bool { onRename != nil || onIconChange != nil }

    var body: some View {
        group
            .onChange(of: focused) { _, isFocused in
                // Click-away voids the edit — commit happens only on Enter.
                if !isFocused && isRenaming { cancel() }
            }
    }

    @ViewBuilder
    private var group: some View {
        let base = stack
            .font(titleFont)
        if interactive {
            base
                .contextMenu {
                    if onRename != nil { Button("Rename") { startRename() } }
                    if onIconChange != nil {
                        Button(icon.isEmpty ? "Add Icon" : "Change Icon") { pickerOpen = true }
                    }
                }
                .iconPickerPopover(isPresented: $pickerOpen, symbol: iconBinding)
        } else {
            base
        }
    }

    @ViewBuilder
    private var stack: some View {
        switch axis {
        case .horizontal:
            HStack(spacing: spacing) {
                iconView
                titleCell
            }
        case .vertical:
            VStack(alignment: horizontalAlignment, spacing: spacing) {
                iconView
                titleCell
            }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if !icon.isEmpty {
            Image(systemName: icon)
                .font(iconFont)
                .foregroundStyle(iconColor ?? .primary)
        }
    }

    @ViewBuilder
    private var titleCell: some View {
        if isRenaming {
            renameField
        } else {
            Text(title.isEmpty ? "Untitled" : title)
                .multilineTextAlignment(textAlignment)
        }
    }

    @ViewBuilder
    private var renameField: some View {
        let field = TextField("Untitled", text: $draft)
            .multilineTextAlignment(textAlignment)
            .focused($focused)
            .onSubmit { commit() }
            .onExitCommand { cancel() }
        let styled = plainField ? AnyView(field.textFieldStyle(.plain)) : AnyView(field)
        if let fieldMaxWidth {
            styled.frame(maxWidth: fieldMaxWidth)
        } else {
            styled
        }
    }

    private var iconBinding: Binding<String?> {
        Binding(
            get: { icon.isEmpty ? nil : icon },
            set: { newIcon in Task { await onIconChange?(newIcon) } }
        )
    }

    /// Enter inline-rename. Focus is deferred so the `TextField` is mounted first.
    private func startRename() {
        draft = title
        isRenaming = true
        DispatchQueue.main.async { focused = true }
    }

    private func commit() {
        isRenaming = false
        focused = false
        onCommitted?()
        let newTitle = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty, newTitle != title else { return }
        Task { await onRename?(newTitle) }
    }

    private func cancel() {
        draft = title
        isRenaming = false
        focused = false
    }
}
