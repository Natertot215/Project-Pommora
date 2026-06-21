import AppKit

/// The chrome-restriction pass applied to the PagePreview panel.
///
/// The preview is a real `NSPanel` (see `PreviewPanel` / `PreviewTarget`) made
/// invisible to the system: no traffic lights, no Window-menu entry, no Cmd-`
/// cycling stop, no Mission Control card, no tab merging, no fullscreen Space,
/// and no title text (the header IS the title bar). The panel manager owns the
/// rest of the window's life (child attachment, close-with-parent).
enum PreviewWindowConfigurator {
    /// The full window-restriction pass — static and window-only so it's unit-
    /// testable without a panel/scene. Idempotent; safe to re-run.
    @MainActor
    static func restrict(_ window: NSWindow) {
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isExcludedFromWindowsMenu = true
        window.tabbingMode = .disallowed
        window.titlebarAppearsTransparent = true
        // The header IS the title bar — clear AND hide the title so no
        // "Page Preview" heading shows.
        window.title = ""
        window.titleVisibility = .hidden
        window.collectionBehavior = [.transient, .ignoresCycle, .fullScreenNone]
    }
}
