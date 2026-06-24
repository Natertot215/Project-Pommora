import Foundation

/// Discriminated union of every sheet the sidebar can present.
///
/// **F.0 system-wide stub-and-inline-rename CRUD refactor:** every "New X"
/// trigger across Pommora now creates the entity immediately with a default
/// title (via `DefaultTitleResolver`) and flips the matching sidebar row
/// into inline-rename mode. The retired `New*Sheet.swift` files (and their
/// `.new*` cases) are gone. Only edit-affordance sheets remain:
/// `editIcon`.
enum SidebarSheet: Identifiable {
    case editIcon(IconTarget)

    /// Disambiguates the icon picker between entity kinds (each manager has its
    /// own updateIcon path).
    enum IconTarget: Hashable {
        case area(Area)
        case topic(Topic)
        case project(Project)
        case pageCollection(PageCollection)
        case pageSetCollection(PageSet)
        case pageSet(PageSet)
        case page(PageMeta, pageCollection: PageCollection, collection: PageSet?, set: PageSet?)
        /// A SavedView on a container (PageCollection or PageSet). Carries IDs
        /// only — the icon write routes through `PageCollectionManager.updateView`,
        /// which resolves the container by ID across both kinds.
        case savedView(viewID: String, containerID: String)
    }

    var id: String {
        switch self {
        case .editIcon(let target):
            switch target {
            case .area(let s): return "editIcon-area-\(s.id)"
            case .topic(let t): return "editIcon-topic-\(t.id)"
            case .project(let p): return "editIcon-project-\(p.id)"
            case .pageCollection(let t): return "editIcon-pageCollection-\(t.id)"
            case .pageSetCollection(let c): return "editIcon-pageSetCollection-\(c.id)"
            case .pageSet(let s): return "editIcon-pageSet-\(s.id)"
            case .page(let p, _, _, _): return "editIcon-page-\(p.id)"
            case .savedView(let viewID, let containerID):
                return "editIcon-savedView-\(containerID)-\(viewID)"
            }
        }
    }
}
