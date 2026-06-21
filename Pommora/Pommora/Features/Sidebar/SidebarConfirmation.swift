import Foundation

/// Discriminated union of every destructive confirmation dialog the sidebar can present.
enum SidebarConfirmation: Identifiable {
    case deleteArea(Area)
    case deleteTopic(Topic)
    case deleteProject(Project)
    case deleteVault(PageType, collectionCount: Int)
    case deleteCollection(PageCollection)
    case deleteSet(PageSet)
    /// Cross-vault whole-Set move that would strip `stripCount` property
    /// values not present in the destination Vault's schema.
    case moveSet(
        PageSet, destination: PageCollection, destinationVault: PageType,
        sourceVault: PageType, stripCount: Int)

    var id: String {
        switch self {
        case .deleteArea(let s): return "deleteArea-\(s.id)"
        case .deleteTopic(let t): return "deleteTopic-\(t.id)"
        case .deleteProject(let p): return "deleteProject-\(p.id)"
        case .deleteVault(let v, _): return "deleteVault-\(v.id)"
        case .deleteCollection(let c): return "deleteCollection-\(c.id)"
        case .deleteSet(let s): return "deleteSet-\(s.id)"
        case .moveSet(let s, _, _, _, _): return "moveSet-\(s.id)"
        }
    }

    /// Title for the confirmation dialog presenting this case.
    var dialogTitle: String {
        switch self {
        case .deleteArea(let s): return "Delete Area \"\(s.title)\"?"
        case .deleteTopic(let t): return "Delete Topic \"\(t.title)\"?"
        case .deleteProject(let p): return "Delete Project \"\(p.title)\"?"
        case .deleteVault(let v, _): return "Delete Vault \"\(v.title)\"?"
        case .deleteCollection(let c): return "Delete Collection \"\(c.title)\"?"
        case .deleteSet(let s): return "Delete Set \"\(s.title)\"?"
        case .moveSet(let s, let dest, let destVault, _, _):
            return "Move Set \"\(s.title)\" to \(destVault.title) › \(dest.title)?"
        }
    }

    /// Body message for the confirmation dialog presenting this case.
    var dialogMessage: String {
        switch self {
        case .deleteArea: return "This action cannot be undone."
        case .deleteTopic: return "This action cannot be undone."
        case .deleteProject: return "This action cannot be undone."
        case .deleteVault(_, let cols): return "Contains \(cols) Collection(s). All contents will be deleted."
        case .deleteCollection: return "All Pages inside will be deleted."
        case .deleteSet:
            return
                "\"Delete Set Only\" moves its Pages up into the Collection. \"Delete Set and Pages\" deletes everything."
        case .moveSet(_, _, _, _, let count):
            return "\(count) property value(s) don't exist in the destination's schema and will be removed."
        }
    }
}
