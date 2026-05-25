import SwiftUI

/// Shared rename-mode row content used by every sidebar row that supports
/// inline rename: Space / Project / PageType / PageCollection / Topic / Page.
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
struct RenameableRow<Trailing: View>: View {
    let symbol: String
    let symbolForeground: Color
    let initialTitle: String
    @Binding var draft: String
    @FocusState.Binding var renameFocused: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onFocusLoss: () -> Void
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
