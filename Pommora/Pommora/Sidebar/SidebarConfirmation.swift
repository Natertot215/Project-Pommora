import Foundation

/// Discriminated union of every destructive confirmation dialog the sidebar can present.
enum SidebarConfirmation: Identifiable {
    case deleteArea(Area)
    case deleteTopic(Topic)
    case deleteProject(Project)
    case deleteVault(PageType, collectionCount: Int)
    case deleteCollection(PageCollection)
    case deleteSet(PageSet)

    var id: String {
        switch self {
        case .deleteArea(let s): return "deleteArea-\(s.id)"
        case .deleteTopic(let t): return "deleteTopic-\(t.id)"
        case .deleteProject(let p): return "deleteProject-\(p.id)"
        case .deleteVault(let v, _): return "deleteVault-\(v.id)"
        case .deleteCollection(let c): return "deleteCollection-\(c.id)"
        case .deleteSet(let s): return "deleteSet-\(s.id)"
        }
    }
}
