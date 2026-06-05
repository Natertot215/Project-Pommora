import Foundation

/// Single source of truth for the `context_links.target_kind` string written when a
/// relation row is indexed. Maps a property's `RelationTarget` to the coarse
/// entity-kind string the `context_links` table stores (`space` / `topic` / `project`).
///
/// Used by `IndexBuilder` (full rebuild) and `IndexUpdater` (incremental upsert)
/// so both paths derive `target_kind` identically.
/// Tier-only tolerance; retired from user creation — only `.contextTier` survives.
enum RelationTargetKind {
    /// `nil` target → `"unknown"` (target kind not yet resolvable at index time).
    /// `nonisolated`: pure value→string mapping, called from `IndexBuilder`'s
    /// off-actor (`nonisolated`) GRDB-write closures (project default isolation is
    /// `@MainActor`, so this must opt out to be callable there).
    nonisolated static func string(from target: PropertyDefinition.RelationTarget?) -> String {
        guard let target else { return "unknown" }
        switch target {
        case .contextTier(let tier):
            switch tier {
            case 1: return "space"
            case 2: return "topic"
            case 3: return "project"
            default: return "context"
            }
        }
    }
}
