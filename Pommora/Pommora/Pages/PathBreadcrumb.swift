import AppKit
import SwiftUI

/// Finder-style breadcrumb — the `>`-separated, clickable path bar — backed by
/// AppKit's `NSPathControl` (the same primitive Finder's path bar uses).
/// Display + click only: the caller maps a clicked index to a navigation
/// action. `isMuted` crumbs render dimmed (used by the transient "back-trail").
struct PathBreadcrumb: NSViewRepresentable {
    struct Crumb: Equatable {
        var title: String
        var isMuted: Bool = false
    }

    let crumbs: [Crumb]
    let onSelect: (Int) -> Void

    func makeNSView(context: Context) -> NSPathControl {
        let control = NSPathControl()
        control.pathStyle = .standard
        control.isEditable = false
        control.backgroundColor = .clear
        control.focusRingType = .none
        control.controlSize = .small
        control.font = NSFont.preferredFont(forTextStyle: .subheadline)
        control.target = context.coordinator
        control.action = #selector(Coordinator.pathItemClicked(_:))
        control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        control.setContentHuggingPriority(.defaultHigh, for: .vertical)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        apply(crumbs, to: control)
        return control
    }

    func updateNSView(_ control: NSPathControl, context: Context) {
        context.coordinator.onSelect = onSelect
        apply(crumbs, to: control)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    private func apply(_ crumbs: [Crumb], to control: NSPathControl) {
        control.pathItems = crumbs.map { crumb in
            let item = NSPathControlItem()
            if crumb.isMuted {
                item.attributedTitle = NSAttributedString(
                    string: crumb.title,
                    attributes: [.foregroundColor: NSColor.tertiaryLabelColor]
                )
            } else {
                item.title = crumb.title
            }
            return item
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSelect: (Int) -> Void

        init(onSelect: @escaping (Int) -> Void) {
            self.onSelect = onSelect
        }

        @objc func pathItemClicked(_ sender: NSPathControl) {
            guard let clicked = sender.clickedPathItem,
                let index = sender.pathItems.firstIndex(of: clicked)
            else { return }
            onSelect(index)
        }
    }
}
