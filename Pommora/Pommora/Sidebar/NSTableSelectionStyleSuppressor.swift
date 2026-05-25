import AppKit
import SwiftUI

/// Disables AppKit's native sidebar selection fill so `SelectionChrome`'s
/// translucent quaternary is the sole selection visual. Walks the host
/// window for the first `NSTableView` — currently unambiguous (sidebar only).
struct NSTableSelectionStyleSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ProbeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // Async hop: NSTableView mounts after the SwiftUI hierarchy settles.
            DispatchQueue.main.async {
                Self.findAndSuppress(in: window.contentView)
            }
        }

        @discardableResult
        static func findAndSuppress(in view: NSView?) -> Bool {
            guard let view else { return false }
            if let table = view as? NSTableView {
                table.selectionHighlightStyle = .none
                return true
            }
            for subview in view.subviews {
                if findAndSuppress(in: subview) { return true }
            }
            return false
        }
    }
}
