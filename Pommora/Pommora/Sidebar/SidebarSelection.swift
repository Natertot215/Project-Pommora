import Foundation

/// What the user has selected in the sidebar. Single source of truth held by
/// ContentView. Detail pane switches on this to choose the right detail view.
enum SidebarSelection: Equatable, Hashable, Sendable {
    case none
    case savedKey(String)  // "homepage" | "calendar" | "recents"
    case space(Space)
    case topic(Topic)
    case subtopic(Subtopic)
    case vault(Vault)
    case collection(Pommora.Collection)
    case page(PageMeta)
}

/// Used by SelectableRow to compare against the current SidebarSelection
/// for highlight state. Each case carries the entity's ULID.
enum SelectionTag: Equatable, Hashable, Sendable {
    case savedKey(String)
    case space(String)
    case topic(String)
    case subtopic(String)
    case vault(String)
    case collection(String)
    case page(String)

    func matches(_ selection: SidebarSelection) -> Bool {
        switch (self, selection) {
        case (.savedKey(let k), .savedKey(let s)): return k == s
        case (.space(let id), .space(let s)): return id == s.id
        case (.topic(let id), .topic(let t)): return id == t.id
        case (.subtopic(let id), .subtopic(let st)): return id == st.id
        case (.vault(let id), .vault(let v)): return id == v.id
        case (.collection(let id), .collection(let c)): return id == c.id
        case (.page(let id), .page(let p)): return id == p.id
        default: return false
        }
    }
}
