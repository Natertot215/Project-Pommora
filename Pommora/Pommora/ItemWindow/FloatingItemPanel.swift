import AppKit
import SwiftUI

/// A non-activating floating panel hosting one Item Window's SwiftUI content.
///
/// `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded` keep the main Pommora window
/// the "main" window — it stays active (no grey-out) while you click and type in
/// this panel; the panel only takes keyboard focus when a control actually needs
/// it. It floats above the main window, is draggable by any empty area, is NOT
/// minimizable (no `.miniaturizable` mask) and NOT user-resizable (no `.resizable`),
/// and uses the standard window background (no custom fill). The panel is ONE fixed
/// size (700×435) — the SwiftUI root is pinned to that size
/// and the inspector takes its share of the width from the body, so toggling it does
/// not grow the panel.
///
/// Lifecycle is owned by `ItemWindowPanelManager` (`isReleasedWhenClosed = false`).
/// `titleVisibility`/`titlebarAppearsTransparent` + `.fullSizeContentView` make the
/// content extend under the title bar. All three native window buttons are hidden;
/// the Item's own header reads as the chrome and supplies a custom ✕ at the top-left.
final class FloatingItemPanel: NSPanel {
    init(rootView: some View) {
        // Zero-dimming: force the hosted content to render in its ACTIVE appearance
        // even when the panel is non-key, so accents / selection / chips never grey
        // out when the main window is clicked. This pins ONLY this panel's content
        // (it makes no claim about key-window status, so the main window is unaffected).
        let hosting = NSHostingController(
            rootView: AnyView(rootView.environment(\.controlActiveState, .active)))
        super.init(
            // 700×435 inlined from the retired PUI.ItemWindow; this file dies in P3.
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 435),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        contentViewController = hosting
        isFloatingPanel = true
        level = .floating
        becomesKeyOnlyIfNeeded = true
        // Scope the float to Pommora. `.floating` level keeps the panel above the
        // main window WHILE Pommora is active (utility-palette behavior, like the
        // system Fonts/Colors panels) — but `.floating` alone leaks across app
        // boundaries, so the panel would sit over OTHER apps too. `hidesOnDeactivate`
        // fixes that: the panel vanishes the moment Pommora is no longer frontmost and
        // reappears on return. (Orthogonal to `.nonactivatingPanel`, which governs
        // focus-stealing, not visibility.)
        hidesOnDeactivate = true
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
        // No `.canJoinAllSpaces` — the panel belongs to the Pommora session, not every
        // desktop. `.fullScreenAuxiliary` lets it appear while the main window is fullscreen.
        collectionBehavior = [.fullScreenAuxiliary]
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // Hide all native traffic-light buttons — the header supplies a custom ✕.
        // `.closable` stays in the style mask so ⌘W still closes the panel.
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }
}
