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
    // MARK: - Shared per-entity resolvers
    //
    // Both bridges below — EntityStateRef→ and SelectionTag→ — resolve the same
    // entities via the same manager lookups. The per-entity resolution lives
    // here ONCE; each `init?` is a thin dispatcher mapping its input kind to a
    // resolver. Adding a selectable entity = one resolver + two one-line
    // dispatch cases, not two duplicated lookup bodies (the prior shape).

    @MainActor
    private static func resolveSpace(id: String, lookup: SidebarLookupBundle) -> SidebarSelection? {
        guard let sm = lookup.space, let s = sm.spaces.first(where: { $0.id == id }) else { return nil }
        return .space(s)
    }

    @MainActor
    private static func resolveTopic(id: String, lookup: SidebarLookupBundle) -> SidebarSelection? {
        guard let tm = lookup.topic, let t = tm.topics.first(where: { $0.id == id }) else { return nil }
        return .topic(t)
    }

    @MainActor
    private static func resolveProject(id: String, lookup: SidebarLookupBundle) -> SidebarSelection? {
        guard let tm = lookup.topic else { return nil }
        for projects in tm.projectsByParent.values {
            if let p = projects.first(where: { $0.id == id }) { return .project(p) }
        }
        return nil
    }

    @MainActor
    private static func resolvePageType(id: String, lookup: SidebarLookupBundle) -> SidebarSelection? {
        guard let pm = lookup.pageType, let t = pm.types.first(where: { $0.id == id }) else { return nil }
        return .pageType(t)
    }

    @MainActor
    private static func resolveCollection(id: String, lookup: SidebarLookupBundle) -> SidebarSelection? {
        guard let pm = lookup.pageType else { return nil }
        for pageType in pm.types {
            if let c = pm.pageCollections(in: pageType).first(where: { $0.id == id }) { return .collection(c) }
        }
        return nil
    }

    @MainActor
    private static func resolvePage(id: String, lookup: SidebarLookupBundle) -> SidebarSelection? {
        guard let cm = lookup.content else { return nil }
        for pages in cm.pagesByCollection.values {
            if let page = pages.first(where: { $0.id == id }) { return .page(page) }
        }
        for pages in cm.pagesByTypeRoot.values {
            if let page = pages.first(where: { $0.id == id }) { return .page(page) }
        }
        return nil
    }

    @MainActor
    private static func resolveItemType(id: String, lookup: SidebarLookupBundle) -> SidebarSelection? {
        guard let itm = lookup.itemType, let t = itm.types.first(where: { $0.id == id }) else { return nil }
        return .itemType(t)
    }

    @MainActor
    private static func resolveItemCollection(id: String, lookup: SidebarLookupBundle) -> SidebarSelection? {
        guard let itm = lookup.itemType else { return nil }
        for itemType in itm.types {
            if let c = itm.itemCollections(in: itemType).first(where: { $0.id == id }) { return .itemCollection(c) }
        }
        return nil
    }

    /// Bridge EntityStateRef → SidebarSelection by resolving via live managers.
    /// Used by NavDropdown's double-click open and BackForwardButtons stepping.
    /// Returns nil for kinds that aren't main-detail-pane targets (item, agenda)
    /// and for entities that no longer exist on disk.
    @MainActor
    init?(stateRef: EntityStateRef, lookup: SidebarLookupBundle) {
        let resolved: SidebarSelection?
        switch stateRef.typedKind {
        case .page: resolved = Self.resolvePage(id: stateRef.id, lookup: lookup)
        case .vault: resolved = Self.resolvePageType(id: stateRef.id, lookup: lookup)
        case .space: resolved = Self.resolveSpace(id: stateRef.id, lookup: lookup)
        case .topic: resolved = Self.resolveTopic(id: stateRef.id, lookup: lookup)
        case .project: resolved = Self.resolveProject(id: stateRef.id, lookup: lookup)
        case .collection: resolved = Self.resolveCollection(id: stateRef.id, lookup: lookup)
        case .itemType: resolved = Self.resolveItemType(id: stateRef.id, lookup: lookup)
        case .set: resolved = Self.resolveItemCollection(id: stateRef.id, lookup: lookup)
        case .item, .agenda, .none: resolved = nil
        }
        guard let resolved else { return nil }
        self = resolved
    }
}

extension SidebarSelection {
    /// Bridge `SelectionTag` → `SidebarSelection` by resolving entities via
    /// live managers. Used by `SidebarView`'s `.onChange(of: selectedTag)` to
    /// keep the entity-bearing `SidebarSelection` binding in sync with the
    /// List's native `selection:` mechanism.
    @MainActor
    init?(tag: SelectionTag, lookup: SidebarLookupBundle) {
        let resolved: SidebarSelection?
        switch tag {
        case .savedKey(let key): resolved = .savedKey(key)
        case .space(let id): resolved = Self.resolveSpace(id: id, lookup: lookup)
        case .topic(let id): resolved = Self.resolveTopic(id: id, lookup: lookup)
        case .project(let id): resolved = Self.resolveProject(id: id, lookup: lookup)
        case .pageType(let id): resolved = Self.resolvePageType(id: id, lookup: lookup)
        case .collection(let id): resolved = Self.resolveCollection(id: id, lookup: lookup)
        case .page(let id): resolved = Self.resolvePage(id: id, lookup: lookup)
        case .itemType(let id): resolved = Self.resolveItemType(id: id, lookup: lookup)
        case .itemCollection(let id): resolved = Self.resolveItemCollection(id: id, lookup: lookup)
        }
        guard let resolved else { return nil }
        self = resolved
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
