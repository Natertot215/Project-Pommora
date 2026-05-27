// EntityRow.swift
import SwiftUI

@MainActor
struct EntityRow: View {
    let ref: EntityStateRef
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

    private var iconName: String {
        switch ref.typedKind {
        case .page: return "doc.text"
        case .vault: return "book"
        case .space: return "rectangle.3.group"
        case .topic: return "folder"
        case .project: return "folder"
        case .folder: return "folder"
        case .item: return "tray"
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
        case .folder: return "Folder"
        case .item: return "Item"
        case .agenda: return "Task"
        case .collection: return "Collection"
        case nil: return ref.kind
        }
    }
}
