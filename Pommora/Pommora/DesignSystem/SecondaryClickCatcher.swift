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

    /// Show `items` as an `NSMenu` on a secondary (right) mouse click. See
    /// `SecondaryClickMenu`.
    func secondaryClickMenu(_ items: [SecondaryClickMenu.Item]) -> some View {
        overlay(SecondaryClickMenu(items: items))
    }
}

/// Pops an `NSMenu` on a secondary (right) mouse click on the attached view,
/// forwarding every other event untouched — same right-mouse-only `hitTest`
/// shim as `SecondaryClickCatcher`, but yielding a menu instead of a closure.
///
/// **Why not `.contextMenu`:** an AppKit-backed sibling beneath the overlay
/// (e.g. the `MarkdownPMEditor`'s `NSTextView`) consumes right-clicks and
/// shows its own menu before SwiftUI's `.contextMenu` ever sees the event.
/// This catcher claims only the right-mouse-down, and AppKit's default
/// dispatch pops the menu returned by `menu(for:)`.
struct SecondaryClickMenu: NSViewRepresentable {
    /// One menu entry: a title + the action it fires.
    struct Item {
        let title: String
        let action: () -> Void

        init(title: String, action: @escaping () -> Void) {
            self.title = title
            self.action = action
        }
    }

    let items: [Item]

    func makeNSView(context: Context) -> NSView {
        let view = MenuView()
        view.items = items
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? MenuView)?.items = items
    }

    final class MenuView: NSView {
        var items: [SecondaryClickMenu.Item] = []

        /// Built at click time so dynamic titles (e.g. "Lock"/"Unlock")
        /// reflect the current state.
        override func menu(for event: NSEvent) -> NSMenu? {
            let menu = NSMenu()
            for (index, item) in items.enumerated() {
                let menuItem = NSMenuItem(
                    title: item.title, action: #selector(run(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.tag = index
                menu.addItem(menuItem)
            }
            return menu
        }

        @objc private func run(_ sender: NSMenuItem) {
            guard items.indices.contains(sender.tag) else { return }
            items[sender.tag].action()
        }

        /// Claim the point ONLY while a right-mouse-down is being dispatched;
        /// every other event passes straight through to the content beneath.
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .rightMouseDown ? self : nil
        }
    }
}
