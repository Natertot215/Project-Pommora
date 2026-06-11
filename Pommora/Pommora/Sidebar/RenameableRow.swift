import AppKit
import SwiftUI

/// Shared rename-mode row content used by every sidebar row that supports
/// inline rename: Area / Project / PageType / PageCollection / Topic / Page.
///
/// Mirrors `SelectableRow`'s HStack shape (icon + text slot + trailing spacer +
/// optional trailing slot) so the row doesn't visually jump when entering or
/// exiting rename mode. Selection chrome stays at the row file level via
/// `.listRowBackground(SelectionChrome(...))` — this helper renders pure
/// content, in line with Paradigm Decision #6.
///
/// State ownership stays with each calling row: `draft`, `isCommitting`, the
/// `@FocusState` itself, and the `commit()` / `cancel()` methods all live in
/// the row. This helper only collapses the duplicated view shape.
///
/// `selectAllOnAppear` (added F.0) drives the system-wide stub-and-inline-
/// rename CRUD flow: when a row is entering rename mode because it was just
/// freshly stub-created (e.g. `"New Folder"` materialized via
/// `CreateWithInlineEdit`), the entire default-title text is selected so the
/// user's first keystroke replaces it. Defaults to `false` so existing
/// rename-from-context-menu sites keep cursor-at-end (their default title
/// already matches the existing entity name, and select-all would surprise).
struct RenameableRow<Trailing: View>: View {
    let symbol: String
    let symbolForeground: Color
    let initialTitle: String
    @Binding var draft: String
    @FocusState.Binding var renameFocused: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onFocusLoss: () -> Void
    let selectAllOnAppear: Bool
    @ViewBuilder let trailing: () -> Trailing

    init(
        symbol: String,
        symbolForeground: Color = .primary,
        initialTitle: String,
        draft: Binding<String>,
        renameFocused: FocusState<Bool>.Binding,
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onFocusLoss: @escaping () -> Void,
        selectAllOnAppear: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.symbol = symbol
        self.symbolForeground = symbolForeground
        self.initialTitle = initialTitle
        self._draft = draft
        self._renameFocused = renameFocused
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.onFocusLoss = onFocusLoss
        self.selectAllOnAppear = selectAllOnAppear
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(symbolForeground)
                .frame(width: 16, height: 16, alignment: .center)
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .focused($renameFocused)
                .onSubmit(onSubmit)
                .onKeyPress(.escape) {
                    onCancel()
                    return .handled
                }
                .onChange(of: renameFocused) { _, focused in
                    if !focused { onFocusLoss() }
                }
                .onAppear {
                    draft = initialTitle
                    renameFocused = true
                    if selectAllOnAppear {
                        // AppKit responder hop. The TextField becomes a
                        // backing NSTextView in the responder chain a tick
                        // after `renameFocused = true`; dispatching to the
                        // next main-runloop pass lets focus settle, then
                        // sending `selectAll:` to the first responder
                        // highlights the entire default-title text so the
                        // user's first keystroke replaces it. Safe no-op if
                        // the responder hasn't materialized yet (the
                        // tryToPerform call silently fails).
                        DispatchQueue.main.async {
                            NSApp.keyWindow?.firstResponder?.tryToPerform(
                                #selector(NSText.selectAll(_:)), with: nil
                            )
                        }
                    }
                }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.leading, 2)
        .padding(.trailing, 0)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
