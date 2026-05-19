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
    /// Bridge EntityRef → SidebarSelection by resolving via AppGlobals.
    /// Returns nil if the underlying entity has been deleted on disk.
    @MainActor
    init?(entityRef: EntityRef) {
        switch entityRef {
        case .page(let pageID, let vaultID, let collectionID):
            guard let cm = AppGlobals.contentManager,
                let vm = AppGlobals.vaultManager,
                let resolved = PageRef(pageID: pageID, vaultID: vaultID, collectionID: collectionID)
                    .resolve(vaultManager: vm, contentManager: cm)
            else { return nil }
            self = .page(resolved.page)
        case .vault(let vaultID):
            guard let vm = AppGlobals.vaultManager,
                let v = vm.vaults.first(where: { $0.id == vaultID })
            else { return nil }
            self = .vault(v)
        case .space(let spaceID):
            guard let sm = AppGlobals.spaceManager,
                let s = sm.spaces.first(where: { $0.id == spaceID })
            else { return nil }
            self = .space(s)
        case .topic(let topicID):
            guard let tm = AppGlobals.topicManager,
                let t = tm.topics.first(where: { $0.id == topicID })
            else { return nil }
            self = .topic(t)
        case .subtopic(let subtopicID, let parentTopicID):
            guard let tm = AppGlobals.topicManager,
                let st = tm.subtopicsByParent[parentTopicID]?.first(where: { $0.id == subtopicID })
            else { return nil }
            self = .subtopic(st)
        case .collection:
            return nil  // not wired in v0.2.7.2
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
