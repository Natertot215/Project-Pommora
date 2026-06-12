import Foundation

/// Shared, tested mutations on a `SavedView`'s `propertyOrder` +
/// `hiddenProperties`. The single source for visibility-toggle semantics —
/// `LayoutPane` calls `applyToggle`; the visibility eye-list builds its
/// candidate columns via `visibilityColumns`. Keeping the logic here (rather
/// than inlined in a view) makes it directly unit-testable and DRY.
enum SavedViewMutations {
    /// Moves `propertyID` between `propertyOrder` and `hiddenProperties`.
    ///
    /// - `_title` is pinned and never toggleable — the call is a no-op.
    /// - Hide (`currentlyVisible == true`): remove from `propertyOrder`,
    ///   append to `hiddenProperties`.
    /// - Un-hide (`currentlyVisible == false`): remove from
    ///   `hiddenProperties`, re-insert into `propertyOrder` right after the
    ///   reserved `_title` lead so it reappears as the leading user column.
    ///
    /// `_modified_at` IS toggleable here (closes the "Modified not hideable"
    /// bug) — only `_title` is exempt.
    static func applyToggle(
        _ view: inout SavedView,
        propertyID: String,
        currentlyVisible: Bool
    ) {
        guard propertyID != ReservedPropertyID.title else { return }

        if currentlyVisible {
            view.propertyOrder.removeAll { $0 == propertyID }
            if !view.hiddenProperties.contains(propertyID) {
                view.hiddenProperties.append(propertyID)
            }
        } else {
            view.hiddenProperties.removeAll { $0 == propertyID }
            if !view.propertyOrder.contains(propertyID) {
                let insertAt = view.propertyOrder.first == ReservedPropertyID.title ? 1 : 0
                view.propertyOrder.insert(propertyID, at: min(insertAt, view.propertyOrder.count))
            }
        }
    }

    /// The Cover sentinel — mirrors `TableColumnResolver.coverID` /
    /// `ViewSettingsProperties.coverID`; cover is never listed in the
    /// visibility eye-list (it's toggled by the Display Banner / cover affordances,
    /// not the column-visibility list).
    static let coverID = "cover"

    /// The per-view visibility-list columns: every resolved schema property
    /// (user properties + the three tier relations) plus the reserved Modified
    /// column, with Cover excluded. `_title` is included (rendered pinned +
    /// non-hideable by the caller). This is the full set of toggleable columns
    /// the Layout pane's eye-list iterates.
    static func visibilityColumns(
        resolved: [PropertyDefinition]
    ) -> [PropertyDefinition] {
        let modified = PropertyDefinition(
            id: ReservedPropertyID.modifiedAt,
            name: "Last edited",
            type: .lastEditedTime,
            icon: "clock.arrow.circlepath"
        )
        return (resolved + [modified]).filter { $0.id != coverID }
    }
}
