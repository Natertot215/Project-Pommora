import Observation

/// Shared inline-rename scaffolding for every sidebar row that supports
/// rename-in-place (Area / Topic / Project / PageCollection / PageCollection /
/// PageSet / Page). Owns the editable `draft` and the in-flight `isCommitting`
/// flag, plus the guard / Task / do-catch shape every row's `commit()`
/// repeated verbatim.
///
/// Each row holds this as `@State private var renameState = InlineRenameState()`
/// and binds `RenameableRow.draft` to `$renameState.draft`. The `@FocusState`
/// stays in the row — property wrappers can't live on an `@Observable` object.
/// The per-row manager call is passed to `commit` as `rename`; clearing the
/// `editingID` / `justCreatedID` bindings is passed as `onCommitted` (the same
/// closure the row uses for cancel / focus-loss), so this type never touches
/// the row's bindings directly.
@MainActor
@Observable
final class InlineRenameState {
    var draft: String = ""
    var isCommitting: Bool = false

    /// Commits an inline rename, preserving the exact per-row behavior:
    /// an unchanged draft clears edit mode without hitting the manager; a
    /// changed draft sets `isCommitting`, awaits `rename`, and on success
    /// clears edit mode — a thrown error leaves edit mode intact for retry
    /// (the manager has already populated `pendingError` for the toast).
    ///
    /// - Parameters:
    ///   - currentTitle: The entity's existing title; an equal draft is a no-op
    ///     rename and only clears edit mode.
    ///   - rename: The manager rename call (e.g. `try await manager.rename(x, to: draft)`).
    ///   - onCommitted: Clears the row's `editingID` / `justCreatedID` bindings.
    ///     Invoked on the unchanged-draft short-circuit and on rename success.
    func commit(
        currentTitle: String,
        rename: @escaping () async throws -> Void,
        onCommitted: @escaping () -> Void
    ) {
        guard draft != currentTitle else {
            onCommitted()
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await rename()
                onCommitted()
            } catch {
                // pendingError set by manager; toast surfaces.
                // edit mode preserved on failure for retry.
            }
        }
    }
}
