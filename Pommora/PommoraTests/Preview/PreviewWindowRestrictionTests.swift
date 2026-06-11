import AppKit
import Testing

@testable import Pommora

/// Verifies the PagePreview window-restriction pass
/// (`PreviewWindowConfigurator.restrict`) — the AppKit setup that hides the
/// "Page Preview" title, hides the traffic-light buttons, excludes the window
/// from system management, and tames the `UtilityWindow` panel's focus defaults.
///
/// These are pure property assertions on real `NSWindow` / `NSPanel` instances
/// (no SwiftUI scene, no `orderFront`), so the suite runs headless. The
/// *interactive* behaviors a window restriction can't express in a unit test —
/// dragging, on-screen focus/dim, the rename click-out — are listed in the
/// manual checklist and are NOT claimed verified here.
@MainActor
@Suite("PreviewWindowRestriction")
struct PreviewWindowRestrictionTests {

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: true)
    }

    private func makePanel() -> NSPanel {
        NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: true)
    }

    @Test("Clears and hides the window title — no 'Page Preview' heading")
    func hidesTitle() {
        let window = makeWindow()
        window.title = "Page Preview"
        PreviewWindowConfigurator.restrict(window)
        #expect(window.title == "")
        #expect(window.titleVisibility == .hidden)
        #expect(window.titlebarAppearsTransparent)
    }

    @Test("Hides the three traffic-light buttons")
    func hidesTrafficLights() {
        let window = makeWindow()
        PreviewWindowConfigurator.restrict(window)
        #expect(window.standardWindowButton(.closeButton)?.isHidden == true)
        #expect(window.standardWindowButton(.miniaturizeButton)?.isHidden == true)
        #expect(window.standardWindowButton(.zoomButton)?.isHidden == true)
    }

    @Test("Excludes the window from menu, tabbing, and cycling")
    func excludesFromManagement() {
        let window = makeWindow()
        PreviewWindowConfigurator.restrict(window)
        #expect(window.isExcludedFromWindowsMenu)
        #expect(window.tabbingMode == .disallowed)
        #expect(window.collectionBehavior.contains(.ignoresCycle))
        #expect(window.collectionBehavior.contains(.fullScreenNone))
    }

    /// The reported bug: the "Page Preview" title reappeared on the 2nd preview.
    /// Simulates SwiftUI re-applying the scene title on a later open, then
    /// re-runs the restriction (exactly what `updateNSView` does on every render)
    /// and confirms the title is hidden again.
    @Test("Re-applying after a SwiftUI title reset re-hides it (2nd-window bug)")
    func reapplyRehidesTitle() {
        let panel = makePanel()
        PreviewWindowConfigurator.restrict(panel)
        // Simulate SwiftUI resetting the title / visibility on the next open.
        panel.title = "Page Preview"
        panel.titleVisibility = .visible
        PreviewWindowConfigurator.restrict(panel)
        #expect(panel.title == "")
        #expect(panel.titleVisibility == .hidden)
    }
}
