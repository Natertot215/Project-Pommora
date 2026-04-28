import Foundation

enum SidebarSection: String, CaseIterable, Identifiable, Codable {
    case favorites
    case folders
    case files
    case tags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorites: return "Favorites"
        case .folders: return "Folders"
        case .files: return "Files"
        case .tags: return "Tags"
        }
    }

    static let defaultOrder: [SidebarSection] = [.favorites, .folders, .files, .tags]

    static func decode(_ stored: String) -> [SidebarSection] {
        let parts = stored.split(separator: ",").map(String.init)
        let parsed = parts.compactMap(SidebarSection.init(rawValue:))
        guard parsed.count == SidebarSection.allCases.count,
              Set(parsed) == Set(SidebarSection.allCases) else {
            return defaultOrder
        }
        return parsed
    }

    static func encode(_ sections: [SidebarSection]) -> String {
        sections.map(\.rawValue).joined(separator: ",")
    }
}
