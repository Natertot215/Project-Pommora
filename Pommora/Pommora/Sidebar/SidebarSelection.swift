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

/// Bundle of live manager refs threaded into `SidebarSelection`'s ID-to-entity
/// resolvers. Replaces the prior `AppGlobals` reads — eliminates the stale-
/// snapshot path that broke sidebar selection on runtime-created entities
/// and toolbar back/forward stepping (v0.3.1.0.1 hotfix).
///
/// Callers (SidebarView / BackForwardButtons / NavDropdownButton) construct
/// a fresh bundle from their `@Environment`-injected managers per resolution.
/// The bundle keeps init signatures small — adding a new manager later means
/// extending this struct, not every call site.
@MainActor
struct SidebarLookupBundle {
    let content: PageContentManager?
    let pageType: PageTypeManager?
    let itemType: ItemTypeManager?
    let space: SpaceManager?
    let topic: TopicManager?
}

extension SidebarSelection {
    /// Bridge EntityStateRef → SidebarSelection by resolving via live managers.
    /// Used by NavDropdown's double-click open and BackForwardButtons stepping.
    /// Returns nil for kinds that aren't main-detail-pane targets (item, agenda,
    /// collection) and for entities that no longer exist on disk.
    @MainActor
    init?(stateRef: EntityStateRef, lookup: SidebarLookupBundle) {
        switch stateRef.typedKind {
        case .page:
            guard let cm = lookup.content else { return nil }
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
            guard let pm = lookup.pageType,
                let t = pm.types.first(where: { $0.id == stateRef.id })
            else { return nil }
            self = .pageType(t)
        case .space:
            guard let sm = lookup.space,
                let s = sm.spaces.first(where: { $0.id == stateRef.id })
            else { return nil }
            self = .space(s)
        case .topic:
            guard let tm = lookup.topic,
                let t = tm.topics.first(where: { $0.id == stateRef.id })
            else { return nil }
            self = .topic(t)
        case .project:
            guard let tm = lookup.topic else { return nil }
            for projects in tm.projectsByParent.values {
                if let p = projects.first(where: { $0.id == stateRef.id }) {
                    self = .project(p)
                    return
                }
            }
            return nil
        case .collection:
            guard let pm = lookup.pageType else { return nil }
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

extension SidebarSelection {
    /// Bridge `SelectionTag` → `SidebarSelection` by resolving entities via
    /// live managers. Used by `SidebarView`'s `.onChange(of: selectedTag)` to
    /// keep the entity-bearing `SidebarSelection` binding in sync with the
    /// List's native `selection:` mechanism.
    @MainActor
    init?(tag: SelectionTag, lookup: SidebarLookupBundle) {
        switch tag {
        case .savedKey(let key):
            self = .savedKey(key)
        case .space(let id):
            guard let sm = lookup.space,
                let s = sm.spaces.first(where: { $0.id == id })
            else { return nil }
            self = .space(s)
        case .topic(let id):
            guard let tm = lookup.topic,
                let t = tm.topics.first(where: { $0.id == id })
            else { return nil }
            self = .topic(t)
        case .project(let id):
            guard let tm = lookup.topic else { return nil }
            for projects in tm.projectsByParent.values {
                if let p = projects.first(where: { $0.id == id }) {
                    self = .project(p)
                    return
                }
            }
            return nil
        case .pageType(let id):
            guard let pm = lookup.pageType,
                let t = pm.types.first(where: { $0.id == id })
            else { return nil }
            self = .pageType(t)
        case .collection(let id):
            guard let pm = lookup.pageType else { return nil }
            for pageType in pm.types {
                if let c = pm.pageCollections(in: pageType).first(where: { $0.id == id }) {
                    self = .collection(c)
                    return
                }
            }
            return nil
        case .page(let id):
            guard let cm = lookup.content else { return nil }
            for pages in cm.pagesByCollection.values {
                if let page = pages.first(where: { $0.id == id }) {
                    self = .page(page)
                    return
                }
            }
            for pages in cm.pagesByTypeRoot.values {
                if let page = pages.first(where: { $0.id == id }) {
                    self = .page(page)
                    return
                }
            }
            return nil
        case .itemType(let id):
            guard let itm = lookup.itemType,
                let t = itm.types.first(where: { $0.id == id })
            else { return nil }
            self = .itemType(t)
        case .itemCollection(let id):
            guard let itm = lookup.itemType else { return nil }
            for itemType in itm.types {
                if let c = itm.itemCollections(in: itemType).first(where: { $0.id == id }) {
                    self = .itemCollection(c)
                    return
                }
            }
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
        // Derive the tag for `selection` and value-compare. Equivalent to the
        // old pairwise switch but doesn't have to grow a case per entity kind —
        // `init?(_:)` is the single source of truth for selection→tag mapping.
        // `.none` yields no tag, so nothing matches it (returns false).
        guard let tag = SelectionTag(selection) else { return false }
        return self == tag
    }

    /// Derive the tag from a `SidebarSelection`. Used by `SidebarView` to keep
    /// the List's native `selection:` state in sync when `SidebarSelection` is
    /// mutated externally (recents jump, programmatic selection after CRUD).
    init?(_ selection: SidebarSelection) {
        switch selection {
        case .none: return nil
        case .savedKey(let k): self = .savedKey(k)
        case .space(let s): self = .space(s.id)
        case .topic(let t): self = .topic(t.id)
        case .project(let p): self = .project(p.id)
        case .pageType(let t): self = .pageType(t.id)
        case .collection(let c): self = .collection(c.id)
        case .page(let p): self = .page(p.id)
        case .itemType(let t): self = .itemType(t.id)
        case .itemCollection(let c): self = .itemCollection(c.id)
        }
    }
}
