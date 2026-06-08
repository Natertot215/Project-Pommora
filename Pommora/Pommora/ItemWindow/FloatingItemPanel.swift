import AppKit
import SwiftUI

/// A non-activating floating panel hosting one Item Window's SwiftUI content.
///
/// `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded` keep the main Pommora window
/// the "main" window — it stays active (no grey-out) while you click and type in
/// this panel; the panel only takes keyboard focus when a control actually needs
/// it. It floats above the main window, is draggable by any empty area, is NOT
/// minimizable (no `.miniaturizable` mask) and NOT user-resizable (no `.resizable`),
/// and uses the standard window background (no custom fill). The hosting controller
/// sizes the panel to its SwiftUI content (`.preferredContentSize`), so the panel
/// fits the content and grows by the inspector's width when it's toggled.
///
/// Lifecycle is owned by `ItemWindowPanelManager` (`isReleasedWhenClosed = false`).
/// `titleVisibility`/`titlebarAppearsTransparent` + `.fullSizeContentView` make the
/// content extend under the title bar, so the Item's own header reads as the chrome
/// with the standard close button flush at the top-left.
final class FloatingItemPanel: NSPanel {
    init(rootView: some View) {
        let hosting = NSHostingController(rootView: AnyView(rootView))
        hosting.sizingOptions = .preferredContentSize
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 540),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        contentViewController = hosting
        isFloatingPanel = true
        level = .floating
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }
}
