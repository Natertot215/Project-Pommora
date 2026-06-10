// EntityRow.swift
import SwiftUI

@MainActor
struct EntityRow: View {
    let ref: EntityStateRef
    /// Used to resolve the entity's current custom icon by id; `EntityStateRef`
    /// itself stores only kind/id/title (no icon), so the icon is resolved live.
    let lookup: SidebarLookupBundle
    let isPinned: Bool
    let pinAction: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(ref.title)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Text(chipText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { hovering = $0 }
        .contextMenu {
            Button(isPinned ? "Unpin \(chipText)" : "Pin \(chipText)") {
                pinAction()
            }
        }
    }

    /// The entity's custom icon if one is set, else the per-kind default glyph.
    /// Resolved live (EntityStateRef stores no icon). Defaults stay outline
    /// (non-`.fill`) variants so an unset entity never reads as a filled state.
    private var iconName: String {
        if let custom = SidebarSelection(stateRef: ref, lookup: lookup)?.resolvedIcon {
            return custom
        }
        return defaultIcon
    }

    private var defaultIcon: String {
        switch ref.typedKind {
        case .page: return "doc.text"
        case .vault: return "book"
        case .space: return "rectangle.3.group"
        case .topic: return "folder"
        case .project: return "folder"
        case .agenda: return "calendar"
        case .collection: return "tray.2"
        case nil: return "questionmark.circle"
        }
    }

    private var chipText: String {
        switch ref.typedKind {
        case .page: return "Page"
        case .vault: return "Vault"
        case .space: return "Space"
        case .topic: return "Topic"
        case .project: return "Project"
        case .agenda: return "Task"
        case .collection: return "Collection"
        case nil: return ref.kind
        }
    }
}
