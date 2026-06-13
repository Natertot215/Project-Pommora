import Foundation

/// Pure decision layer for a table row drag-drop. Given the dragged rows (their
/// page ids + the group they came from) and where they landed (a target group +
/// an insertion index), it returns the single committable `Plan`. Side-effect
/// free and SwiftUI-free so `GroupDropPlannerTests` can exercise every branch
/// without a running table.
///
/// Only PAGE rows are drag sources — a group-row source (or any non-page source)
/// resolves to `.none`. Group rows are drop TARGETS only; the wiring never makes
/// them draggable, and the planner refuses them as sources defensively.
enum GroupDropPlanner {

    /// What kind of group a drag endpoint sits in — the structural-vs-property
    /// distinction that decides whether a cross-group drop is a file move or a
    /// property rewrite. Mirrors `ResolvedGroup.Kind` minus the entity payloads
    /// the planner doesn't need (it routes by `PageParent`, supplied separately).
    enum GroupContext: Equatable, Sendable {
        /// A structural container (Collection or Set, or the vault root). Carries
        /// the `PageParent` a move would target.
        case structural(PageParent)
        /// A property bucket — `value` nil = the `_ungrouped` "No <Property>" bucket.
        case property(value: String?)
    }

    /// The source endpoint of the drag.
    struct Source: Equatable, Sendable {
        /// The dragged page ids (multi-drag bound to the table selection).
        let pageIDs: [String]
        /// `true` when the drag originates from real page rows. A group-row or
        /// otherwise non-page source is `false` → the plan is always `.none`.
        let isPageRows: Bool
        /// The group the rows were lifted from.
        let group: GroupContext
        /// The structural parent the source rows currently live under — drives the
        /// reorder index space and the move source.
        let parent: PageParent
    }

    /// The drop endpoint.
    struct Target: Equatable, Sendable {
        let group: GroupContext
        /// Row insertion index within the target's items (used only by `.reorder`).
        let insertionIndex: Int
    }

    /// The committable outcome — an exhaustive closed set the caller switches on.
    enum Plan: Equatable, Sendable {
        /// Manual-sort reorder within the SAME container. The commit translates
        /// the moving ids + insertion anchor to the stored-array order, so the
        /// plan itself carries no offsets.
        case reorder
        /// Drop into a different STRUCTURAL group → a real file move.
        case move(to: PageParent)
        /// Drop into a PROPERTY bucket → rewrite `id` to the bucket's `value`
        /// (nil for the ungrouped bucket).
        case rewriteProperty(id: String, value: String?)
        /// Invalid — non-page source, or a same-container drop while sorted.
        case none
    }

    /// Resolve the plan.
    ///
    /// - `sortIsManual`: the active view has no sort (`sort == nil`); only then
    ///   may a same-container drop reorder.
    /// - `groupPropertyID`: the active group's property id, needed to know WHICH
    ///   property a property-bucket drop rewrites. Nil when not property-grouped.
    static func plan(
        source: Source,
        target: Target,
        sortIsManual: Bool,
        groupPropertyID: String?
    ) -> Plan {
        // Only page rows are drag sources — everything else is invalid.
        guard source.isPageRows, !source.pageIDs.isEmpty else { return .none }

        switch target.group {
        case .property(let value):
            // A property-bucket drop rewrites the grouped property to the bucket
            // value (ungrouped bucket → nil). Needs to know the property.
            guard let propertyID = groupPropertyID else { return .none }
            // Same bucket as the source: a reorder if manual, else a no-op.
            if case .property(let sourceValue) = source.group, sourceValue == value {
                return sortIsManual ? .reorder : .none
            }
            return .rewriteProperty(id: propertyID, value: value)

        case .structural(let destination):
            // Same structural container as the source → reorder (manual only).
            if case .structural = source.group, source.parent == destination {
                return sortIsManual ? .reorder : .none
            }
            // Different structural container → a real file move.
            return .move(to: destination)
        }
    }
}

/// Inverts `GroupResolver.bucketKey` — turns a property bucket's string key back
/// into the typed `PropertyValue` a property-bucket drop must write (nil bucket /
/// nil result = clear the property). Keyed off the schema's property type so the
/// rewrite matches the on-disk encoding (Select/Status/Checkbox).
enum BucketValueDecoder {
    static func propertyValue(
        bucket: String?, propertyID: String, schema: [PropertyDefinition]
    ) -> PropertyValue? {
        guard let bucket else { return nil }
        switch schema.first(where: { $0.id == propertyID })?.type {
        case .status: return .status(bucket)
        case .checkbox: return .checkbox(bucket == "true")
        case .select: return .select(bucket)
        default: return .select(bucket)
        }
    }
}
