// EntityRow.swift
import SwiftUI

@MainActor
struct EntityRow: View {
    let ref: EntityStateRef
    let isFavorite: Bool
    let favoriteAction: () -> Void
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

            heartIcon
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var heartIcon: some View {
        if isFavorite || hovering {
            Button {
                favoriteAction()
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 12))
                    .foregroundStyle(isFavorite ? Color.pink : .secondary)
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            .frame(width: 16)
        } else {
            Color.clear.frame(width: 16)  // reserves space; row width stable
        }
    }

    private var iconName: String {
        switch ref.typedKind {
        case .page: return "doc.text"
        case .vault: return "book"
        case .space: return "rectangle.3.group"
        case .topic: return "folder"
        case .subtopic: return "folder"
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
        case .subtopic: return "Sub-topic"
        case .item: return "Item"
        case .agenda: return "Task"  // chip label override per spec
        case .collection: return "Collection"
        case nil: return ref.kind
        }
    }
}
