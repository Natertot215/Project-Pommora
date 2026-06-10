import AppKit
import SwiftUI

/// The AppKit restriction pass on the SwiftUI-created PagePreview window —
/// the one place the V9 design touches NSWindow directly (plan §Architecture).
///
/// A preview is a real window in the hand but invisible to the system:
/// - no traffic lights (the three standard buttons are hidden);
/// - no Window-menu entry, no Cmd-` cycling stop, no Mission Control card,
///   no tab merging, no fullscreen Space;
/// - attached as a CHILD of the main window at normal level, so it rides
///   along when Pommora moves, always stays above the main window, never
///   floats over other apps, and hides/minimizes with the app;
/// - closes itself when the main window closes (AppKit does NOT do this for
///   children) and re-asserts its chrome if SwiftUI re-renders reset it.
///
/// Mounted as a zero-size `.background` of the window content; configuration
/// runs in `viewDidMoveToWindow` and is idempotent. Observers are
/// selector-based (not closure-based) — window notifications arrive on the
/// main thread and `@objc` methods on this `@MainActor` view sidestep the
/// `@Sendable` capture rules closure observers would trip (quirk #5).
struct PreviewWindowConfigurator: NSViewRepresentable {
    /// Surfaces the live NSWindow to SwiftUI state so the inspector toggle
    /// can animate the frame (widen/shrink) deterministically.
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> ConfiguratorView {
        ConfiguratorView(onWindow: { window = $0 })
    }

    func updateNSView(_ nsView: ConfiguratorView, context: Context) {}

    @MainActor
    final class ConfiguratorView: NSView {
        private let onWindow: (NSWindow?) -> Void
        private var configuredWindow: NSWindow?

        init(onWindow: @escaping (NSWindow?) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("unused") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window = self.window, window !== configuredWindow else { return }
            if configuredWindow != nil {
                NotificationCenter.default.removeObserver(self)
            }
            configuredWindow = window
            configure(window)
            attachToMainWindow(window)
            NotificationCenter.default.addObserver(
                self, selector: #selector(ownWindowDidBecomeKey(_:)),
                name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(
                self, selector: #selector(someWindowWillClose(_:)),
                name: NSWindow.willCloseNotification, object: nil)
            // Defer the SwiftUI state write out of the layout pass.
            let report = onWindow
            DispatchQueue.main.async { report(window) }
        }

        /// Idempotent chrome restriction — safe to re-run after SwiftUI
        /// scene re-renders (re-applied on every key activation).
        private func configure(_ window: NSWindow) {
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isExcludedFromWindowsMenu = true
            window.tabbingMode = .disallowed
            window.titlebarAppearsTransparent = true
            // Hidden from Mission Control (.transient), out of Cmd-`
            // (.ignoresCycle), never its own fullscreen Space
            // (.fullScreenNone). Children do NOT inherit these — set here.
            window.collectionBehavior = [.transient, .ignoresCycle, .fullScreenNone]
        }

        /// Child attachment: ride main-window moves, stack above the parent,
        /// stay at normal level (never over other apps). No-op when already
        /// attached or when the main window isn't up yet (retried on key).
        private func attachToMainWindow(_ window: NSWindow) {
            guard window.parent == nil,
                let main = AppGlobals.mainWindow, main !== window
            else { return }
            main.addChildWindow(window, ordered: .above)
        }

        /// SwiftUI has historically re-asserted titlebar-adjacent properties
        /// on scene updates; re-apply chrome + attachment on every key
        /// activation (both are idempotent).
        @objc private func ownWindowDidBecomeKey(_ note: Notification) {
            guard let window = configuredWindow else { return }
            configure(window)
            attachToMainWindow(window)
        }

        /// AppKit orphans (not closes) children when the parent closes —
        /// close ourselves when the main window goes away. Detach first so
        /// the closing parent's responder chain can't dangle into us
        /// (radar 20166537).
        @objc private func someWindowWillClose(_ note: Notification) {
            guard let window = configuredWindow,
                let closing = note.object as? NSWindow,
                closing === window.parent
            else { return }
            closing.removeChildWindow(window)
            window.close()
        }
    }
}
