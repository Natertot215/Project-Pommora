import AppKit
import SwiftUI

/// The PagePreview window, owned by us as a real `NSPanel`.
///
/// A regular `NSPanel` (NOT `.nonactivatingPanel`) is, by default, exactly the
/// three things the preview needs and that no SwiftUI scene type can express
/// together:
/// - **activating** — clicking it brings Pommora forward (refocus-from-outside);
/// - **never main** — it can't become the main window, so it never demotes (and
///   dims) the real main window: preview + main read as one focus unit;
/// - **key-capable** — it still takes keyboard focus for the inline title field.
///
/// Owning the window is the only safe route: SwiftUI's `WindowGroup` window is a
/// private `AppKitWindow` that crashes when reclassed to override `canBecomeMain`.
@MainActor
final class PreviewPanel: NSPanel {
    // NSPanel already returns false here, but be explicit — this is the property
    // the whole no-dim behavior hinges on.
    override var canBecomeMain: Bool { false }
}

/// Owns the single PagePreview panel: opens / retargets it for a `PageRef`,
/// hosts the shared `PagePreviewContent` SwiftUI view inside it, child-attaches
/// it to the main window, and tears it down (explicit close / Nexus switch /
/// main-window close).
@MainActor
final class PreviewTarget {
    static let shared = PreviewTarget()
    private init() {}

    private var panel: PreviewPanel?
    private var parentCloseObserver: (any NSObjectProtocol)?

    /// Open — or retarget + focus — the preview panel for `pageRef`.
    func open(_ pageRef: PageRef) {
        guard let env = AppGlobals.current else { return }
        let host = NSHostingView(rootView: PagePreviewContent(ref: pageRef).injectNexusEnvironment(env))

        if let panel {
            panel.contentView = host
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = PreviewPanel(
            contentRect: NSRect(origin: .zero, size: PreviewWindowMetrics.defaultSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = false          // child-attached above main, not floating over other apps
        panel.hidesOnDeactivate = false        // stay visible when the app is in the background
        panel.becomesKeyOnlyIfNeeded = false   // take key on click (title editing)
        panel.isReleasedWhenClosed = false     // we hold the only strong ref; release by nil-ing `panel`
        panel.contentMinSize = PreviewWindowMetrics.minBodySize
        panel.contentView = host
        PreviewWindowConfigurator.restrict(panel)

        if let main = AppGlobals.mainWindow {
            // Child of the main window: rides its moves, stacks above it, never
            // floats over other apps, hides with the app.
            main.addChildWindow(panel, ordered: .above)
            // AppKit does NOT close children with their parent — do it ourselves.
            parentCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: main, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.close() }
            }
        }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    /// Close + tear down the panel (idempotent).
    func close() {
        if let parentCloseObserver {
            NotificationCenter.default.removeObserver(parentCloseObserver)
            self.parentCloseObserver = nil
        }
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.close()
        }
        panel = nil
    }
}

/// The ONE open-path for the preview (DRY) — the panel is owned and managed
/// directly by `PreviewTarget`; no SwiftUI window action is involved.
@MainActor
func openPagePreview(_ ref: PageRef) {
    PreviewTarget.shared.open(ref)
}
