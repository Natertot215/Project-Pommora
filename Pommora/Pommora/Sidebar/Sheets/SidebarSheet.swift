import Foundation

/// Discriminated union of every sheet the sidebar can present.
enum SidebarSheet: Identifiable {
    case newSpace
    case newTopic
    case newProject(parent: Topic)
    case newPageType
    case newCollection(pageType: PageType)
    case newPage(collection: PageCollection, pageType: PageType)
    case newPageInPageType(pageType: PageType)
    case newItemType
    case newItemCollection(type: ItemType)
    case newItem(collection: ItemCollection?, type: ItemType)
    case editTopicParents(Topic)
    case editIcon(IconTarget)
    case editColor(Space)

    /// Disambiguates the icon picker between entity kinds (each manager has its
    /// own updateIcon path).
    enum IconTarget: Hashable {
        case space(Space)
        case topic(Topic)
        case project(Project)
        case pageType(PageType)
        case itemType(ItemType)
    }

    var id: String {
        switch self {
        case .newSpace: return "newSpace"
        case .newTopic: return "newTopic"
        case .newProject(let t): return "newProject-\(t.id)"
        case .newPageType: return "newPageType"
        case .newCollection(let t): return "newCollection-\(t.id)"
        case .newPage(let c, _): return "newPage-\(c.id)"
        case .newPageInPageType(let t): return "newPageInPageType-\(t.id)"
        case .newItemType: return "newItemType"
        case .newItemCollection(let t): return "newItemCollection-\(t.id)"
        case .newItem(let c, let t): return "newItem-\(c?.id ?? t.id)"
        case .editTopicParents(let t): return "editTopicParents-\(t.id)"
        case .editIcon(let target):
            switch target {
            case .space(let s): return "editIcon-space-\(s.id)"
            case .topic(let t): return "editIcon-topic-\(t.id)"
            case .project(let p): return "editIcon-project-\(p.id)"
            case .pageType(let t): return "editIcon-pageType-\(t.id)"
            case .itemType(let t): return "editIcon-itemType-\(t.id)"
            }
        case .editColor(let s): return "editColor-\(s.id)"
        }
    }
}
