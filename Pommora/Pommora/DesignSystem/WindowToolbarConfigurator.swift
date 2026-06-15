import SwiftUI
import AppKit

/// Suppresses the native AppKit `NSToolbar` right-click display-mode menu
/// ("Icon Only / Icon and Text") that macOS auto-attaches to every toolbar a
/// SwiftUI `.toolbar { }` materializes. Pommora's chrome is a fixed custom
/// design, so the display-mode toggle is noise — confirmed (06-14) to be the
/// system menu, not app code, via a live `NSToolbar` introspection probe.
///
/// The earlier attempt set `allowsDisplayModeCustomization = false` too early,
/// before SwiftUI had attached the toolbar, so it never landed. This waits until
/// `window.toolbar` exists (deferred one run-loop tick) and **re-asserts on every
/// `updateNSView`** — navigation adds/removes the conditional Views pill, which
/// makes SwiftUI rebuild the `NSToolbar` and reset the property back to `true`.
///
/// Suppresses ONLY the display-mode menu; other toolbar right-click behavior is
/// untouched. Hosted on the `NavigationSplitView` via `.background(...)`.
struct WindowToolbarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfiguratorView { ConfiguratorView() }

    func updateNSView(_ nsView: ConfiguratorView, context: Context) {
        nsView.applyWhenReady()
    }

    /// Plain `NSView` — drives application through `perform(_:afterDelay:)`
    /// (main run loop, no `@Sendable` closure) so it stays clean under Swift 6
    /// strict concurrency.
    final class ConfiguratorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyWhenReady()
        }

        func applyWhenReady() {
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            perform(#selector(apply), with: nil, afterDelay: 0)
        }

        @objc private func apply() {
            guard let toolbar = window?.toolbar else {
                // Toolbar not attached yet (or mid-rebuild) — retry shortly.
                perform(#selector(apply), with: nil, afterDelay: 0.2)
                return
            }
            if toolbar.allowsDisplayModeCustomization {
                toolbar.allowsDisplayModeCustomization = false
            }
        }
    }
}
