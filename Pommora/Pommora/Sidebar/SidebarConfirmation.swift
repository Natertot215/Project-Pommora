import Foundation

/// Discriminated union of every destructive confirmation dialog the sidebar can present.
enum SidebarConfirmation: Identifiable {
    case deleteSpace(Space)
    case deleteTopic(Topic, subtopicCount: Int)
    case deleteSubtopic(Subtopic)
    case deleteVault(PageType, collectionCount: Int)
    case deleteCollection(PageCollection)

    var id: String {
        switch self {
        case .deleteSpace(let s): return "deleteSpace-\(s.id)"
        case .deleteTopic(let t, _): return "deleteTopic-\(t.id)"
        case .deleteSubtopic(let s): return "deleteSubtopic-\(s.id)"
        case .deleteVault(let v, _): return "deleteVault-\(v.id)"
        case .deleteCollection(let c): return "deleteCollection-\(c.id)"
        }
    }
}
