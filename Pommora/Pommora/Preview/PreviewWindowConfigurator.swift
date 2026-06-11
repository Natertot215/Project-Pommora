import AppKit
import SwiftUI

/// The AppKit restriction pass on the SwiftUI-created PagePreview window.
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
/// The host scene is a `WindowGroup` with the secondary `.associated` window-
/// manager role: a normal window (so clicking it activates the app — refocus
/// from the background works natively), marked dependent so it reads as a
/// satellite of the main window rather than a co-equal primary.
struct PreviewWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfiguratorView { ConfiguratorView() }
    func updateNSView(_ nsView: ConfiguratorView, context: Context) {
        // SwiftUI re-applies the scene title (and can reset titleVisibility) on
        // later opens / content retargets — re-run the restriction on every
        // update so the title stays hidden on the 2nd, 3rd, … preview. Idempotent.
        nsView.reapplyRestrictions()
    }

    /// The full window-restriction pass — static and window-only so it's unit-
    /// testable without a SwiftUI scene. Idempotent; safe to re-run.
    @MainActor
    static func restrict(_ window: NSWindow) {
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isExcludedFromWindowsMenu = true
        window.tabbingMode = .disallowed
        window.titlebarAppearsTransparent = true
        // The header IS the title bar — clear AND hide the title so no
        // "Page Preview" heading shows (SwiftUI sets it from the scene title).
        window.title = ""
        window.titleVisibility = .hidden
        window.collectionBehavior = [.transient, .ignoresCycle, .fullScreenNone]
    }

    @MainActor
    final class ConfiguratorView: NSView {
        private var configuredWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window = self.window, window !== configuredWindow else { return }
            if configuredWindow != nil {
                NotificationCenter.default.removeObserver(self)
            }
            configuredWindow = window
            PreviewWindowConfigurator.restrict(window)
            attachToMainWindow(window)
            NotificationCenter.default.addObserver(
                self, selector: #selector(ownWindowDidBecomeKey(_:)),
                name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(
                self, selector: #selector(someWindowWillClose(_:)),
                name: NSWindow.willCloseNotification, object: nil)
        }

        // Pure window accessor — never intercept clicks, so the SwiftUI content
        // (its WindowDragGesture areas and controls) receives them all.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// Re-run the window restriction (called on every SwiftUI update so the
        /// title stays hidden across repeated opens / retargets).
        func reapplyRestrictions() {
            guard let window else { return }
            PreviewWindowConfigurator.restrict(window)
        }

        /// Child attachment: ride main-window moves, stack above the parent,
        /// stay at normal level (never over other apps).
        private func attachToMainWindow(_ window: NSWindow) {
            guard window.parent == nil,
                let main = AppGlobals.mainWindow, main !== window
            else { return }
            main.addChildWindow(window, ordered: .above)
        }

        @objc private func ownWindowDidBecomeKey(_ note: Notification) {
            guard let window = configuredWindow else { return }
            PreviewWindowConfigurator.restrict(window)
            attachToMainWindow(window)
        }

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
