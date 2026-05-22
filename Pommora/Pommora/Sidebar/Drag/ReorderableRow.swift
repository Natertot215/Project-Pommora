import SwiftUI

/// Position the dragged row should land relative to the target row.
enum DropPosition: Sendable {
    case above
    case below
}

/// View modifier that turns a sidebar row into both a drag source and a drop
/// destination for sibling reorder (v0.2.8.0). Stays inside `List` and
/// `.listStyle(.sidebar)` so all of the existing visual chrome —
/// `SelectionChrome`, DisclosureGroup chevron + child indentation,
/// sidebar focus/key-window semantics — is preserved exactly.
///
/// Drop visualization: a faint accent stroke (1pt, accentColor at 40% opacity,
/// inset to match `SelectionChrome`'s 11pt horizontal + 2pt vertical padding)
/// appears while the row is the drop target. No "live shuffle as I drag"
/// reflow — that's a `LazyVStack`-only effect; here, the array reflows on
/// drop release with `withAnimation(.snappy)`.
///
/// Call from any row's outer view container (e.g. wrapped around
/// `SelectableRow` or applied to a `DisclosureGroup`'s label).
struct ReorderableRowModifier: ViewModifier {
    let kind: SidebarDragPayload.Kind
    let id: String
    let containerID: String?
    let isVaultRoot: Bool
    let nexusID: String
    let symbol: String
    let title: String
    let accent: Color?
    let onDrop: @MainActor (SidebarDragPayload, DropPosition) -> Void

    @State private var rowHeight: CGFloat = 0
    @State private var isTargeted: Bool = false

    func body(content: Content) -> some View {
        content
            .draggable(makePayload()) {
                SidebarDragPreview(symbol: symbol, title: title, accent: accent)
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                rowHeight = newHeight
            }
            .dropDestination(for: SidebarDragPayload.self) { payloads, location in
                guard let payload = payloads.first else { return false }
                guard DragValidator.canAccept(payload, on: target()) else { return false }
                let position: DropPosition =
                    (rowHeight > 0 && location.y > rowHeight / 2) ? .below : .above
                withAnimation(.snappy(duration: 0.18)) {
                    onDrop(payload, position)
                }
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
            .overlay(alignment: .center) {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.40), lineWidth: 1)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 2)
                        .allowsHitTesting(false)
                }
            }
    }

    private func makePayload() -> SidebarDragPayload {
        SidebarDragPayload(
            kind: kind,
            id: id,
            containerID: containerID,
            isVaultRoot: isVaultRoot,
            nexusID: nexusID
        )
    }

    private func target() -> DragValidator.Target {
        DragValidator.Target(
            kind: kind,
            id: id,
            containerID: containerID,
            isVaultRoot: isVaultRoot,
            nexusID: nexusID
        )
    }
}

extension View {
    /// Make this row a drag source and a sibling-reorder drop target. See
    /// `ReorderableRowModifier` for visual semantics.
    func reorderable(
        kind: SidebarDragPayload.Kind,
        id: String,
        containerID: String? = nil,
        isVaultRoot: Bool = false,
        nexusID: String,
        symbol: String,
        title: String,
        accent: Color? = nil,
        onDrop: @escaping @MainActor (SidebarDragPayload, DropPosition) -> Void
    ) -> some View {
        modifier(
            ReorderableRowModifier(
                kind: kind,
                id: id,
                containerID: containerID,
                isVaultRoot: isVaultRoot,
                nexusID: nexusID,
                symbol: symbol,
                title: title,
                accent: accent,
                onDrop: onDrop
            )
        )
    }
}
