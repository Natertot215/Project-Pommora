import SwiftUI

/// Shared, app-wide resolver: a context-link/tier target ID → its current display
/// (icon + title). Render surfaces call `resolve(_:)` SYNCHRONOUSLY during
/// layout, so the host must `warm(_:)` the needed IDs first (async, off the
/// index); resolved values land in the cache and `resolve` is a pure dict read.
/// One instance is injected at `ContentView` and shared by every surface —
/// the single source of truth for context-link display resolution (DRY).
@Observable
@MainActor
final class ContextDisplayResolver {
    private var cache: [String: EntityRef] = [:]
    private let index: () -> PommoraIndex?

    init(index: @escaping () -> PommoraIndex?) { self.index = index }

    /// Synchronous render-time read. Returns nil for un-warmed / unknown IDs.
    func resolve(_ id: String) -> (icon: String, title: String)? {
        guard let ref = cache[id] else { return nil }
        return (ref.icon ?? Self.defaultIcon(for: ref.kind), ref.title)
    }

    /// Full cached entity (kind / title / icon) for an ID, or nil if un-warmed /
    /// unknown. Future-proofs a context-chip redesign that may style by kind or
    /// color; `resolve(_:)` stays the lightweight icon+title accessor.
    func entity(_ id: String) -> EntityRef? {
        cache[id]
    }

    /// Batch-load IDs into the cache. Call from `.task`/`.onChange` when the
    /// visible relation/tier values change. Already-cached IDs are skipped.
    func warm(_ ids: [String]) async {
        let missing = ids.filter { cache[$0] == nil }
        guard !missing.isEmpty, let idx = index() else { return }
        let resolved = (try? await IndexQuery(idx).resolveEntities(ids: missing)) ?? [:]
        for (id, ref) in resolved { cache[id] = ref }
    }

    /// Drop the cache after a rename/icon edit so the next warm re-reads.
    func invalidate() { cache.removeAll() }

    static func defaultIcon(for kind: EntityKind) -> String {
        switch kind {
        case .page, .pageType, .pageCollection, .pageSet: return "doc.text"
        case .area: return "square.stack.3d.up"
        case .topic: return "folder"
        case .project: return "list.bullet.rectangle"
        case .agendaTask: return "checklist"
        case .agendaEvent: return "calendar"
        }
    }
}
