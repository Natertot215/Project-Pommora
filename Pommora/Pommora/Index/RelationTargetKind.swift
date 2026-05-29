import Foundation

/// Single source of truth for the `relations.target_kind` string written when a
/// relation row is indexed. Maps a property's `RelationTarget` to the coarse
/// entity-kind string the `relations` table stores (`page` / `item` /
/// `space` / `topic` / `project` / `agenda_task` / `agenda_event`).
///
/// Used by `IndexBuilder` (full rebuild) and intended for `IndexUpdater`
/// (incremental upsert) so both paths derive `target_kind` identically.
/// Container targets (`pageType` / `pageCollection` → `page`; `itemType` /
/// `itemCollection` → `item`) collapse to the contained entity's kind, since
/// the relation points at the entities inside the container, not the container.
enum RelationTargetKind {
    /// `nil` target → `"unknown"` (target kind not yet resolvable at index time).
    /// `nonisolated`: pure value→string mapping, called from `IndexBuilder`'s
    /// off-actor (`nonisolated`) GRDB-write closures (project default isolation is
    /// `@MainActor`, so this must opt out to be callable there).
    nonisolated static func string(from target: PropertyDefinition.RelationTarget?) -> String {
        guard let target else { return "unknown" }
        switch target {
        case .pageType, .pageCollection: return "page"
        case .itemType, .itemCollection: return "item"
        case .contextTier(let tier):
            switch tier {
            case 1: return "space"
            case 2: return "topic"
            case 3: return "project"
            default: return "context"
            }
        case .agendaTasks:  return "agenda_task"
        case .agendaEvents: return "agenda_event"
        }
    }
}
