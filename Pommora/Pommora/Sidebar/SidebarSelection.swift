import Foundation

/// What the user has selected in the sidebar. Single source of truth held by
/// ContentView. Detail pane switches on this to choose the right detail view.
enum SidebarSelection: Equatable, Hashable, Sendable {
    case none
    case savedKey(String)  // "homepage" | "calendar" | "recents"
    case space(Space)
    case topic(Topic)
    case project(Project)
    case pageType(PageType)
    case collection(PageCollection)
    case page(PageMeta)
    case itemType(ItemType)
    case itemCollection(ItemCollection)
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
            for pages in cm.pagesByTypeRoot.values {
                if let page = pages.first(where: { $0.id == stateRef.id }) {
                    self = .page(page)
                    return
                }
            }
            return nil
        case .vault:
            guard let pm = AppGlobals.pageTypeManager,
                let t = pm.types.first(where: { $0.id == stateRef.id })
            else { return nil }
            self = .pageType(t)
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
        case .project:
            guard let tm = AppGlobals.topicManager else { return nil }
            for projects in tm.projectsByParent.values {
                if let p = projects.first(where: { $0.id == stateRef.id }) {
                    self = .project(p)
                    return
                }
            }
            return nil
        case .collection:
            guard let pm = AppGlobals.pageTypeManager else { return nil }
            for pageType in pm.types {
                if let c = pm.pageCollections(in: pageType).first(where: { $0.id == stateRef.id }) {
                    self = .collection(c)
                    return
                }
            }
            return nil
        case .item, .agenda, .none:
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
    case project(String)
    case pageType(String)
    case collection(String)
    case page(String)
    case itemType(String)
    case itemCollection(String)

    func matches(_ selection: SidebarSelection) -> Bool {
        switch (self, selection) {
        case (.savedKey(let k), .savedKey(let s)): return k == s
        case (.space(let id), .space(let s)): return id == s.id
        case (.topic(let id), .topic(let t)): return id == t.id
        case (.project(let id), .project(let p)): return id == p.id
        case (.pageType(let id), .pageType(let t)): return id == t.id
        case (.collection(let id), .collection(let c)): return id == c.id
        case (.page(let id), .page(let p)): return id == p.id
        case (.itemType(let id), .itemType(let t)): return id == t.id
        case (.itemCollection(let id), .itemCollection(let c)): return id == c.id
        default: return false
        }
    }
}
