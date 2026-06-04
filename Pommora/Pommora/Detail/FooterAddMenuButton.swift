import SwiftUI
import AppKit

/// The `+` button in detail-view footers. Uses a native `NSMenu` presented via
/// `popUp(positioning:at:in:)` so AppKit's screen-edge detection keeps the menu
/// inside the window — SwiftUI's `Menu` wrapper doesn't expose the anchor point
/// and can escape below the Dock when the button sits at the bottom of the pane.
struct FooterAddMenuButton: View {
    struct Item {
        let label: String
        var isDisabled: Bool = false
        let action: () -> Void
    }

    let items: [Item]
    var allDisabled: Bool = false

    var body: some View {
        _FooterMenuNSButton(items: items, allDisabled: allDisabled)
            .frame(width: 20, height: 20)
    }
}

// MARK: - AppKit bridge

private final class _ActionBox {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
}

private struct _FooterMenuNSButton: NSViewRepresentable {
    let items: [FooterAddMenuButton.Item]
    let allDisabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.clicked(_:))
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        nsView.image = NSImage(systemSymbolName: "plus",
                               accessibilityDescription: "Add")?
            .withSymbolConfiguration(config)
        nsView.contentTintColor = .labelColor
        nsView.isEnabled = !allDisabled
        context.coordinator.items = items
    }

    final class Coordinator: NSObject {
        var items: [FooterAddMenuButton.Item] = []

        @objc func clicked(_ sender: NSButton) {
            let menu = NSMenu()
            for item in items {
                let mi = NSMenuItem(title: item.label,
                                   action: #selector(fire(_:)),
                                   keyEquivalent: "")
                mi.target = self
                mi.isEnabled = !item.isDisabled
                mi.representedObject = _ActionBox(item.action)
                menu.addItem(mi)
            }
            // Anchor at the top-left of the button; AppKit flips upward
            // automatically when the menu would otherwise go off-screen.
            menu.popUp(positioning: menu.items.first,
                       at: NSPoint(x: 0, y: sender.bounds.height),
                       in: sender)
        }

        @objc func fire(_ sender: NSMenuItem) {
            (sender.representedObject as? _ActionBox)?.run()
        }
    }
}
