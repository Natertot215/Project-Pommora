import AppKit

/// Selects all text in the key window's first responder on the next main-runloop
/// pass — used right after focusing an inline-rename field so the default title
/// is highlighted and the user's first keystroke replaces it.
///
/// The one-tick defer lets the SwiftUI `TextField`'s backing `NSText` enter the
/// responder chain first; a safe no-op if the responder hasn't materialized yet
/// (`tryToPerform` silently fails). Shared by the sidebar's row + section rename.
enum InlineRenameFocus {
    static func selectAllOnNextRunloop() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.firstResponder?.tryToPerform(
                #selector(NSText.selectAll(_:)), with: nil)
        }
    }
}
