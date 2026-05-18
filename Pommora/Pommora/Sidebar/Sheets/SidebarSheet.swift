import Foundation

/// Discriminated union of every sheet the sidebar can present.
enum SidebarSheet: Identifiable {
    case newSpace
    case newTopic
    case newSubtopic(parent: Topic)
    case newVault
    case newCollection(vault: Vault)
    case newPage(collection: Pommora.Collection, vault: Vault)
    case newPageInVault(vault: Vault)
    case newItem(collection: Pommora.Collection, vault: Vault)
    case editTopicParents(Topic)
    case editIcon(IconTarget)
    case editColor(Space)

    /// Disambiguates the icon picker between entity kinds (each manager has its
    /// own updateIcon path).
    enum IconTarget: Hashable {
        case space(Space)
        case topic(Topic)
        case subtopic(Subtopic)
        case vault(Vault)
    }

    var id: String {
        switch self {
        case .newSpace: return "newSpace"
        case .newTopic: return "newTopic"
        case .newSubtopic(let t): return "newSubtopic-\(t.id)"
        case .newVault: return "newVault"
        case .newCollection(let v): return "newCollection-\(v.id)"
        case .newPage(let c, _): return "newPage-\(c.id)"
        case .newPageInVault(let v): return "newPageInVault-\(v.id)"
        case .newItem(let c, _): return "newItem-\(c.id)"
        case .editTopicParents(let t): return "editTopicParents-\(t.id)"
        case .editIcon(let target):
            switch target {
            case .space(let s): return "editIcon-space-\(s.id)"
            case .topic(let t): return "editIcon-topic-\(t.id)"
            case .subtopic(let s): return "editIcon-subtopic-\(s.id)"
            case .vault(let v): return "editIcon-vault-\(v.id)"
            }
        case .editColor(let s): return "editColor-\(s.id)"
        }
    }
}
