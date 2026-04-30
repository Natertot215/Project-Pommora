import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorites: return "Favorites"
        }
    }
}
