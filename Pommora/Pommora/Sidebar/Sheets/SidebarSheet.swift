import Foundation

/// Discriminated union of every sheet the sidebar can present.
///
/// **F.0 system-wide stub-and-inline-rename CRUD refactor:** every "New X"
/// trigger across Pommora now creates the entity immediately with a default
/// title (via `DefaultTitleResolver`) and flips the matching sidebar row
/// into inline-rename mode. The retired `New*Sheet.swift` files (and their
/// `.newSpace` / `.newTopic` / `.newProject` / `.newPageType` /
/// `.newCollection` / `.newPage` / `.newPageInPageType` / `.newItemType` /
/// `.newItemCollection` / `.newItem` cases) are gone. Only edit-affordance
/// sheets remain: `editTopicParents`, `editIcon`, `editColor`.
enum SidebarSheet: Identifiable {
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
