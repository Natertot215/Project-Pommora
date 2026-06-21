import SwiftUI

/// Identity view for Area / Topic / Project selection (and the Page load-failure
/// state) — the entity's icon + title. When `onRename` / `onIconChange` are
/// supplied it gains the shared title interaction (right-click → Rename / Change
/// Icon, inline rename, anchored picker); without them it's display-only.
struct ContextDetailPlaceholder: View {
    let title: String
    let icon: String
    let accent: Color?
    let supportingLine: String?
    var onRename: ((String) async -> Void)? = nil
    var onIconChange: ((String?) async -> Void)? = nil

    @State private var isRenaming = false
    @State private var draft = ""
    @State private var pickerOpen = false
    @FocusState private var focused: Bool

    private var interactive: Bool { onRename != nil || onIconChange != nil }

    var body: some View {
        VStack(spacing: PUI.Spacing.xl) {
            titleGroup
            if let supportingLine {
                Text(supportingLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: focused) { _, isFocused in
            if !isFocused && isRenaming { commit() }
        }
    }

    @ViewBuilder
    private var titleGroup: some View {
        let group = VStack(spacing: PUI.Spacing.md) {
            Image(systemName: icon)
                .font(PUI.Typography.Fixed.f48)
                .foregroundStyle(accent ?? .secondary)
            if isRenaming {
                TextField("Untitled", text: $draft)
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .focused($focused)
                    .onSubmit { commit() }
                    .onExitCommand { cancel() }
            } else {
                Text(title.isEmpty ? "Untitled" : title)
                    .font(.title)
            }
        }
        if interactive {
            group
                .contextMenu {
                    if onRename != nil { Button("Rename") { startRename() } }
                    if onIconChange != nil {
                        Button(icon.isEmpty ? "Add Icon" : "Change Icon") { pickerOpen = true }
                    }
                }
                .iconPickerPopover(isPresented: $pickerOpen, symbol: iconBinding)
        } else {
            group
        }
    }

    private var iconBinding: Binding<String?> {
        Binding(get: { icon.isEmpty ? nil : icon }, set: { new in Task { await onIconChange?(new) } })
    }

    private func startRename() {
        draft = title
        isRenaming = true
        DispatchQueue.main.async { focused = true }
    }

    private func commit() {
        isRenaming = false
        focused = false
        let newTitle = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty, newTitle != title else { return }
        Task { await onRename?(newTitle) }
    }

    private func cancel() {
        isRenaming = false
        focused = false
    }
}
