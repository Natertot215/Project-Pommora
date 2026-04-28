import Foundation

enum SidebarSelection: Hashable {
    case recents
    case folder(UUID)
    case file(UUID)
}
