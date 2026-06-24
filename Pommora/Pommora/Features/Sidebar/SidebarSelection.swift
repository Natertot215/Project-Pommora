import Foundation

/// What the user has selected in the sidebar. Single source of truth held by
/// ContentView. Detail pane switches on this to choose the right detail view.
enum SidebarSelection: Equatable, Hashable, Sendable {
    case none
    case savedKey(String)  // "homepage" | "calendar" | "recents"
    case area(Area)
    case topic(Topic)
    case project(Project)
    case pageType(PageType)
    case collection(PageSet)
    case page(PageMeta)
}

extension SidebarSelection {
    /// The resolved entity's custom icon (SF Symbol name), or nil when unset or
    /// empty. Lets render surfaces (e.g. Navigation rows) override their
    /// per-kind default glyph with the entity's current icon — "default unless
    /// the entity sets one."
    var resolvedIcon: String? {
        let raw: String?
        switch self {
        case .page(let p): raw = p.frontmatter.icon
        case .pageType(let t): raw = t.icon
        case .collection(let c): raw = c.icon
        case .area(let s): raw = s.icon
        case .topic(let t): raw = t.icon
        case .project(let p): raw = p.icon
        case .none, .savedKey: raw = nil
        }
        return raw.nonEmpty
    }
}

/// Bundle of live manager refs threaded into `SidebarSelection`'s ID-to-entity
/// resolvers. Replaces the prior `AppGlobals` reads — eliminates the stale-
/// snapshot path that broke sidebar selection on runtime-created entities
/// and toolbar back/forward stepping (v0.3.1.0.1 hotfix).
///
/// Callers (SidebarView / BackForwardButtons / NavigationButton) construct
/// a fresh bundle from their `@Environment`-injected managers per resolution.
/// The bundle keeps init signatures small — adding a new manager later means
/// extending this struct, not every call site.
@MainActor
struct SidebarLookupBundle {
    let content: PageContentManager?
    let pageType: PageTypeManager?
    let area: AreaManager?
    let topic: TopicManager?
    let project: ProjectManager?
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
    private static func resolveArea(id: String, lookup: SidebarLookupBundle) -> SidebarSelection? {
        guard let sm = lookup.area, let s = sm.areas.first(where: { $0.id == id }) else { return nil }
        return .area(s)
    }

    @MainActor
    private static func resolveTopic(id: String, lookup: SidebarLookupBundle) -> SidebarSelection? {
        guard let tm = lookup.topic, let t = tm.topics.first(where: { $0.id == id }) else { return nil }
        return .topic(t)
    }

    @MainActor
    private static func resolveProject(id: String, lookup: SidebarLookupBundle) -> SidebarSelection? {
        guard let pm = lookup.project, let p = pm.projects.first(where: { $0.id == id }) else { return nil }
        return .project(p)
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
        for pages in cm.pagesBySet.values {
            if let page = pages.first(where: { $0.id == id }) { return .page(page) }
        }
        for pages in cm.pagesByTypeRoot.values {
            if let page = pages.first(where: { $0.id == id }) { return .page(page) }
        }
        return nil
    }


    /// Bridge EntityStateRef → SidebarSelection by resolving via live managers.
    /// Used by Navigation's double-click open and BackForwardButtons stepping.
    /// Returns nil for kinds that aren't main-detail-pane targets (agenda)
    /// and for entities that no longer exist on disk.
    @MainActor
    init?(stateRef: EntityStateRef, lookup: SidebarLookupBundle) {
        let resolved: SidebarSelection?
        switch stateRef.typedKind {
        case .page: resolved = Self.resolvePage(id: stateRef.id, lookup: lookup)
        case .vault: resolved = Self.resolvePageType(id: stateRef.id, lookup: lookup)
        case .area: resolved = Self.resolveArea(id: stateRef.id, lookup: lookup)
        case .topic: resolved = Self.resolveTopic(id: stateRef.id, lookup: lookup)
        case .project: resolved = Self.resolveProject(id: stateRef.id, lookup: lookup)
        case .collection: resolved = Self.resolveCollection(id: stateRef.id, lookup: lookup)
        case .agenda, .none: resolved = nil
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
        case .area(let id): resolved = Self.resolveArea(id: id, lookup: lookup)
        case .topic(let id): resolved = Self.resolveTopic(id: id, lookup: lookup)
        case .project(let id): resolved = Self.resolveProject(id: id, lookup: lookup)
        case .pageType(let id): resolved = Self.resolvePageType(id: id, lookup: lookup)
        case .collection(let id): resolved = Self.resolveCollection(id: id, lookup: lookup)
        case .page(let id): resolved = Self.resolvePage(id: id, lookup: lookup)
        // Sets have no detail view — a .set tag resolves to nothing, which
        // SidebarView's `.onChange` guard treats as "do nothing" (the current
        // selection is NOT cleared).
        case .set: resolved = nil
        }
        guard let resolved else { return nil }
        self = resolved
    }
}

/// Used by SelectableRow to compare against the current SidebarSelection
/// for highlight state. Each case carries the entity's ULID.
enum SelectionTag: Equatable, Hashable, Sendable {
    case savedKey(String)
    case area(String)
    case topic(String)
    case project(String)
    case pageType(String)
    case collection(String)
    case page(String)
    /// Identity-only tag for PageSet rows. Gives each Set row a distinct row
    /// identity inside `List(selection:)` so it never inherits an enclosing
    /// container's tag (the v0.4.1 selection-bleed bug). Never produced by
    /// `init?(_ selection:)` — `SidebarSelection` has no Set case — so
    /// `matches(_:)` is always false and Set rows never paint as selected.
    case set(String)

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
        case .area(let s): self = .area(s.id)
        case .topic(let t): self = .topic(t.id)
        case .project(let p): self = .project(p.id)
        case .pageType(let t): self = .pageType(t.id)
        case .collection(let c): self = .collection(c.id)
        case .page(let p): self = .page(p.id)
        }
    }
}
