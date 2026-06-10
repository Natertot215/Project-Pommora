import Foundation

/// Discriminated union of every destructive confirmation dialog the sidebar can present.
enum SidebarConfirmation: Identifiable {
    case deleteSpace(Space)
    case deleteTopic(Topic)
    case deleteProject(Project)
    case deleteVault(PageType, collectionCount: Int)
    case deleteCollection(PageCollection)

    var id: String {
        switch self {
        case .deleteSpace(let s): return "deleteSpace-\(s.id)"
        case .deleteTopic(let t): return "deleteTopic-\(t.id)"
        case .deleteProject(let p): return "deleteProject-\(p.id)"
        case .deleteVault(let v, _): return "deleteVault-\(v.id)"
        case .deleteCollection(let c): return "deleteCollection-\(c.id)"
        }
    }
}
