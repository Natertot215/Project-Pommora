import Foundation

/// What the user has selected in the sidebar. Single source of truth held by
/// ContentView. Detail pane switches on this to choose the right detail view.
enum SidebarSelection: Equatable, Hashable, Sendable {
    case none
    case savedKey(String)            // "homepage" | "calendar" | "recents"
    case space(Space)
    case topic(Topic)
    case subtopic(Subtopic)
    case vault(Vault)
    case collection(Pommora.Collection)
}
