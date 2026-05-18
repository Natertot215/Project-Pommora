import Foundation

/// Unified row value for Pages + Items inside a Collection. Used by the
/// detail-pane Tables so a single column can render both kinds uniformly.
enum ContentItem: Identifiable, Hashable, Sendable {
    case page(PageMeta)
    case item(Item)

    var id: String {
        switch self {
        case .page(let p): return "page-\(p.id)"
        case .item(let i): return "item-\(i.id)"
        }
    }

    var title: String {
        switch self {
        case .page(let p): return p.title
        case .item(let i): return i.title
        }
    }

    var kindLabel: String {
        switch self {
        case .page: return "Page"
        case .item: return "Item"
        }
    }

    var iconName: String {
        switch self {
        case .page(let p): return p.frontmatter.icon ?? "doc.text"
        case .item(let i): return i.icon ?? "list.bullet.rectangle"
        }
    }

    var modifiedAt: Date {
        switch self {
        case .page(let p): return p.frontmatter.createdAt  // PageMeta doesn't carry mtime; fall back to createdAt
        case .item(let i): return i.modifiedAt
        }
    }
}
