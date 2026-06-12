import SwiftUI

/// Observable store that owns the table row-drag mechanic. Separates visual
/// state from commit logic so `CustomTableView` stays pure of planner details:
///
///   - `update(_:)` — receives a resolved `DropContext` on hover and updates
///     `insertion` / `highlightedGroupID` for the view to render live feedback.
///   - `drop(payload:context:)` — runs `GroupDropPlanner` on commit and
///     dispatches the resulting plan to the injected commit closures.
///
/// Page rows use `.draggable` + `dropDestination`; the payload is ID-only so
/// all structural context is resolved by the view and passed in via `DropContext`.
@MainActor
@Observable
final class RowDragCoordinator {

    // MARK: - Commit closures (injected by the detail view)

    /// Reorder within a container: `(movingIDs, anchorID, parent)` — the moving
    /// page ids and the page id the drop lands BEFORE (nil = append). The detail
    /// view routes to the matching id-based `reorderPages` overload by parent,
    /// which resolves stored-array offsets internally (so a reorder inside a
    /// property bucket / filtered subset stays correct).
    var reorder: ([String], String?, PageParent) -> Void = { _, _, _ in }
    /// Move pages to a different structural container: `(pageIDs, source, destination)`.
    var move: ([String], PageParent, PageParent) -> Void = { _, _, _ in }
    /// Rewrite a property on pages: `(pageIDs, propertyID, value)` (nil = clear).
    var rewriteProperty: ([String], String, String?) -> Void = { _, _, _ in }

    // MARK: - Observable visual state

    /// The active insertion line — a (groupID, row index) pair the view draws a
    /// divider above. Nil when the drop would not reorder (move / rewrite / none).
    private(set) var insertion: InsertionMarker?
    /// The group currently highlighted as a move / rewrite target. Nil otherwise.
    private(set) var highlightedGroupID: String?

    struct InsertionMarker: Equatable {
        let groupID: String
        let index: Int
    }

    // MARK: - Live drag geometry (drives the hover preview off `session.location`)

    /// Per-row frames in the shared GLOBAL coordinate space (`.global`),
    /// keyed by `ViewItem.id`. Captured by each rendered row via `onGeometryChange`
    /// and read back in `onDropSessionUpdated` to hit-test the drop location. The
    /// live insertion line + group highlight derive from THIS + `session.location`,
    /// never from `draggedItemIDs` (per-row `.draggable` registers no container).
    private(set) var rowFrames: [String: CGRect] = [:]
    /// Per-CARD frames in the same global space, keyed by `ViewItem.id` — the
    /// gallery's parallel to `rowFrames`. Separate registry so the grid hit-test
    /// (`GalleryDropGeometry`, horizontal-midpoint flow order) never collides with
    /// the table's vertical-midpoint use; a detail view drives only one renderer.
    private(set) var cardFrames: [String: CGRect] = [:]
    /// Per-group-header frames in the same space, keyed by `ResolvedGroup.id`.
    private(set) var groupFrames: [String: CGRect] = [:]
    /// The page ids of the row(s) currently being dragged — stamped at drag start
    /// so the hover math can exclude source rows / size a count. Independent of the
    /// drop-session payload (which is nil mid-flight for per-row `.draggable`).
    private(set) var draggedIDs: [String] = []

    func setRowFrame(_ id: String, _ frame: CGRect) { rowFrames[id] = frame }
    func setCardFrame(_ id: String, _ frame: CGRect) { cardFrames[id] = frame }
    func setGroupFrame(_ id: String, _ frame: CGRect) { groupFrames[id] = frame }
    func beginDrag(_ ids: [String]) { draggedIDs = ids }

    // MARK: - Drop context (resolved by the view from the render tree)

    /// Everything `GroupDropPlanner` needs that only the view can resolve. The
    /// view builds this at drop / hover time from the target row + its own state.
    struct DropContext {
        let source: GroupDropPlanner.Source
        let target: GroupDropPlanner.Target
        let sortIsManual: Bool
        let groupPropertyID: String?
        let sourceIndices: IndexSet
        /// The target group's stable id — drives the insertion-line / highlight.
        let targetGroupID: String
        /// The page id the drop lands BEFORE within the target group, or nil to
        /// append. Routed to the id-based reorder commit so it translates to the
        /// manager's stored-array offsets (group subset can differ from the full
        /// container under property-grouping / an active filter).
        let anchorID: String?
    }

    // MARK: - Hover update (insertion line + highlight)

    /// Recompute the visual markers for an in-flight drop. Called from
    /// `onDropSessionUpdated`. A reorder plan shows the insertion line; a move /
    /// rewrite highlights the target group; `.none` clears both.
    func update(_ context: DropContext?) {
        guard let context else {
            insertion = nil
            highlightedGroupID = nil
            return
        }
        switch plan(for: context) {
        case .reorder:
            insertion = InsertionMarker(
                groupID: context.targetGroupID, index: context.target.insertionIndex)
            highlightedGroupID = nil
        case .move, .rewriteProperty:
            insertion = nil
            highlightedGroupID = context.targetGroupID
        case .none:
            insertion = nil
            highlightedGroupID = nil
        }
    }

    /// Clear all visual state — call when the drag leaves / ends.
    func clear() {
        insertion = nil
        highlightedGroupID = nil
        draggedIDs = []
    }

    // MARK: - Commit

    /// Plan + dispatch a completed drop. Returns whether anything committed.
    @discardableResult
    func drop(payload: ViewRowDragPayload, context: DropContext) -> Bool {
        defer { clear() }
        switch plan(for: context) {
        case .reorder:
            // The planner's offsets index the group SUBSET; route the moving ids
            // + anchor through the id-based reorder commit, which resolves the
            // manager's stored-array offsets (correct under property-grouping /
            // an active filter where the subset ≠ the full container).
            reorder(context.source.pageIDs, context.anchorID, context.source.parent)
            return true
        case .move(let destination):
            move(payload.pageIDs, context.source.parent, destination)
            return true
        case .rewriteProperty(let id, let value):
            rewriteProperty(payload.pageIDs, id, value)
            return true
        case .none:
            return false
        }
    }

    private func plan(for context: DropContext) -> GroupDropPlanner.Plan {
        GroupDropPlanner.plan(
            source: context.source,
            target: context.target,
            sortIsManual: context.sortIsManual,
            groupPropertyID: context.groupPropertyID,
            sourceIndices: context.sourceIndices)
    }

    // MARK: - Context resolution (shared by both detail views)

    /// Build a `DropContext` for a drop of `draggedItems` onto `targetGroup` at
    /// `insertionIndex`. Pure: both `PageTypeDetailView` and
    /// `PageCollectionDetailView` call this with the knowledge only they hold —
    /// the active view's `group` config + `sort`, and a `structuralParent`
    /// resolver that maps a structural `ResolvedGroup` to its `PageParent` (it
    /// knows the scope's vault / collection). Returns nil when the drag is
    /// invalid (no items, or the source page isn't resolvable to a group).
    static func makeContext(
        draggedItems: [ViewItem],
        targetGroup: ResolvedGroup,
        insertionIndex: Int,
        anchorID: String?,
        group: GroupConfig?,
        sortIsManual: Bool,
        sourceIndices: IndexSet,
        structuralParent: (ResolvedGroup) -> PageParent?
    ) -> DropContext? {
        guard let firstSource = draggedItems.first else { return nil }
        let groupPropertyID: String? = {
            if case .property(let grouping)? = group { return grouping.propertyID }
            return nil
        }()

        guard
            let sourceGroup = context(for: firstSource, group: group),
            let targetGroupContext = context(
                for: targetGroup, structuralParent: structuralParent,
                ungroupedFallback: firstSource.parent)
        else { return nil }

        let source = GroupDropPlanner.Source(
            pageIDs: draggedItems.map(\.id),
            isPageRows: true,
            group: sourceGroup,
            parent: firstSource.parent)
        let target = GroupDropPlanner.Target(
            group: targetGroupContext, insertionIndex: insertionIndex)

        return DropContext(
            source: source,
            target: target,
            sortIsManual: sortIsManual,
            groupPropertyID: groupPropertyID,
            sourceIndices: sourceIndices,
            targetGroupID: targetGroup.id,
            anchorID: anchorID)
    }

    /// A dragged page's group context — its property bucket when property-grouped,
    /// else its structural container (from the stamped `PageParent`).
    private static func context(
        for item: ViewItem, group: GroupConfig?
    ) -> GroupDropPlanner.GroupContext? {
        if case .property(let grouping)? = group {
            return .property(value: bucketValue(item, propertyID: grouping.propertyID))
        }
        return .structural(item.parent)
    }

    /// A target group's context — property buckets map straight across; a
    /// structural group resolves its `PageParent` via the injected resolver.
    private static func context(
        for resolved: ResolvedGroup,
        structuralParent: (ResolvedGroup) -> PageParent?,
        ungroupedFallback: PageParent
    ) -> GroupDropPlanner.GroupContext? {
        switch resolved.kind {
        case .propertyBucket(let value):
            return .property(value: value)
        case .structuralCollection, .structuralSet:
            guard let parent = structuralParent(resolved) else { return nil }
            return .structural(parent)
        case .ungrouped:
            // The headerless / no-container band has no group entity to move
            // into: route to the source's own structural parent so an in-band
            // drop reads as a same-container reorder.
            return .structural(ungroupedFallback)
        }
    }

    /// The grouped property's bucket key for a page (Select / Status / Checkbox),
    /// nil = the page has no value (the `_ungrouped` bucket). Mirrors
    /// `GroupResolver.bucketKey`.
    private static func bucketValue(_ item: ViewItem, propertyID: String) -> String? {
        switch item.page.frontmatter.properties[propertyID] {
        case .select(let s), .status(let s): return s
        case .checkbox(let b): return b ? "true" : "false"
        default: return nil
        }
    }
}
