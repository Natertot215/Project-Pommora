import AppKit
import SwiftUI

/// Owns the live floating Item panels — one `FloatingItemPanel` per open `ItemRef`.
/// Re-opening an already-open Item brings its panel to the front (dedup by `ItemRef`).
/// Each panel hosts `ItemWindowHost` (the ref→VM→renderer→inspector content), which
/// injects the live per-Nexus environment itself. Resolves the env from
/// `AppGlobals.current` at open time (the same source the old scene root used).
///
/// Reached via `AppGlobals.current?.itemWindowPanelManager` (a stored property on
/// `NexusEnvironment`); it is NOT injected into the SwiftUI environment, so it needs
/// no `@Observable`. It's an `NSObject` so it can be each panel's `NSWindowDelegate`
/// and clean the registry up on close.
@MainActor
final class ItemWindowPanelManager: NSObject, NSWindowDelegate {
    private var panels: [ItemRef: FloatingItemPanel] = [:]

    /// Opens (or brings to front) the floating panel for `ref`.
    func open(_ ref: ItemRef) {
        if let existing = panels[ref] {
            existing.orderFront(nil)  // non-activating bring-to-front (NOT makeKeyAndOrderFront)
            return
        }
        guard let env = AppGlobals.current else { return }
        let panel = FloatingItemPanel(rootView: ItemWindowHost(ref: ref, env: env))
        panel.delegate = self
        panels[ref] = panel
        panel.orderFront(nil)  // present without activating; panel keys itself when a field needs it
    }

    /// Closes the panel for `ref` (the inspector's Delete calls this after deleting).
    func close(_ ref: ItemRef) {
        panels[ref]?.close()  // triggers `windowWillClose` → registry cleanup
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? FloatingItemPanel else { return }
        panels = panels.filter { $0.value !== panel }
    }
}
