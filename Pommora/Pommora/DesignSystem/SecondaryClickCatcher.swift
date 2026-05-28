import SwiftUI
import AppKit

/// Fires a closure on a secondary (right) mouse click on the attached view.
///
/// **Why AppKit:** macOS SwiftUI has no native right-click *gesture* — a
/// right-click is conventionally an `NSMenu` (`.contextMenu`). To open the
/// inline `OptionEditPopover` directly on right-click (per Nathan's 2026-05-27
/// direction — right-click + double-click both open the editor), this small
/// shim intercepts only the right-mouse event and forwards everything else
/// untouched to the SwiftUI content beneath.
///
/// The catcher is applied as an `.overlay`, but its `hitTest` returns `self`
/// **only while the current event is a right-mouse event** — for every other
/// event it returns `nil`, so left clicks, double-clicks, and drags pass
/// straight through to the underlying view.
struct SecondaryClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.action = action
    }

    final class CatcherView: NSView {
        var action: (() -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            action?()
        }

        /// Claim the point ONLY while a right-mouse-down is being dispatched
        /// (so this view receives `rightMouseDown(with:)`); for every other
        /// event return nil so left clicks, double-clicks, and `.draggable`
        /// drags pass straight through to the SwiftUI content beneath.
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .rightMouseDown ? self : nil
        }
    }
}

extension View {
    /// Run `action` on a secondary (right) mouse click. See
    /// `SecondaryClickCatcher`.
    func onSecondaryClick(perform action: @escaping () -> Void) -> some View {
        overlay(SecondaryClickCatcher(action: action))
    }
}
