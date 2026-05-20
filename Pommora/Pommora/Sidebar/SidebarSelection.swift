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

extension SidebarSelection {
    /// Bridge EntityStateRef → SidebarSelection by resolving via AppGlobals.
    /// Used by NavDropdown's double-click open and BackForwardButtons stepping.
    /// Returns nil for kinds that aren't main-detail-pane targets (item, agenda,
    /// collection) and for entities that no longer exist on disk.
    @MainActor
    init?(stateRef: EntityStateRef) {
        switch stateRef.typedKind {
        case .page:
            guard let cm = AppGlobals.contentManager else { return nil }
            for pages in cm.pagesByCollection.values {
                if let page = pages.first(where: { $0.id == stateRef.id }) {
                    self = .page(page)
                    return
                }
            }
            for pages in cm.pagesByVaultRoot.values {
                if let page = pages.first(where: { $0.id == stateRef.id }) {
                    self = .page(page)
                    return
                }
            }
            return nil
        case .vault:
            guard let vm = AppGlobals.vaultManager,
                let v = vm.vaults.first(where: { $0.id == stateRef.id })
            else { return nil }
            self = .vault(v)
        case .space:
            guard let sm = AppGlobals.spaceManager,
                let s = sm.spaces.first(where: { $0.id == stateRef.id })
            else { return nil }
            self = .space(s)
        case .topic:
            guard let tm = AppGlobals.topicManager,
                let t = tm.topics.first(where: { $0.id == stateRef.id })
            else { return nil }
            self = .topic(t)
        case .subtopic:
            guard let tm = AppGlobals.topicManager else { return nil }
            for subs in tm.subtopicsByParent.values {
                if let st = subs.first(where: { $0.id == stateRef.id }) {
                    self = .subtopic(st)
                    return
                }
            }
            return nil
        case .collection, .item, .agenda, .none:
            return nil
        }
    }
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
