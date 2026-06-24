import Foundation

/// Shared, tested mutations on a `SavedView`'s `propertyOrder` +
/// `hiddenProperties`. The single source for visibility-toggle semantics —
/// `LayoutPane` calls `applyToggle`; the visibility eye-list builds its
/// candidate columns via `visibilityColumns`. Keeping the logic here (rather
/// than inlined in a view) makes it directly unit-testable and DRY.
enum SavedViewMutations {
    /// Toggles `propertyID` in `hiddenProperties` — visibility is membership
    /// only; `propertyOrder` is never touched.
    ///
    /// - `_title` is pinned and never toggleable — the call is a no-op.
    /// - Hide (`currentlyVisible == true`): append to `hiddenProperties` (if
    ///   not already present). `propertyOrder` is left intact so the row keeps
    ///   its position in the single ordered list.
    /// - Un-hide (`currentlyVisible == false`): remove from `hiddenProperties`.
    ///   Position in `propertyOrder` is preserved automatically.
    ///
    /// If a property being hidden is not yet in `propertyOrder`, no insertion
    /// is made — the caller's drag-reorder owns `propertyOrder` mutations.
    /// `_modified_at` IS toggleable — only `_title` is exempt.
    static func applyToggle(
        _ view: inout SavedView,
        propertyID: String,
        currentlyVisible: Bool
    ) {
        guard propertyID != ReservedPropertyID.title else { return }

        if currentlyVisible {
            if !view.hiddenProperties.contains(propertyID) {
                view.hiddenProperties.append(propertyID)
            }
        } else {
            view.hiddenProperties.removeAll { $0 == propertyID }
        }
    }

    /// Scrubs every dangling reference to a now-deleted schema `propertyID`
    /// from a single view's config so the resolvers never see an id without a
    /// backing definition. The single source for delete-time view cleanup —
    /// `PageCollectionManager.deleteProperty` maps this across all of a container's
    /// views.
    ///
    /// - Drops `sort` criteria whose `propertyID` matches (clearing `sort` to
    ///   nil when nothing remains, so the Sort pane shows "unsorted" honestly).
    /// - Resets `group` to `.structural` when it groups by the deleted property
    ///   (otherwise every page collapses into one "No Value" bucket).
    /// - Removes the id from `propertyOrder` and `hiddenProperties`.
    /// - Drops the id's entry from `columnWidths`.
    ///
    /// `collapsedGroups` is intentionally LEFT untouched — those are group
    /// *keys* (a property's values), not property ids.
    static func scrubDeletedProperty(_ view: inout SavedView, propertyID: String) {
        if var sort = view.sort {
            sort.removeAll { $0.propertyID == propertyID }
            view.sort = sort.isEmpty ? nil : sort
        }
        if case .property(let grouping) = view.group, grouping.propertyID == propertyID {
            view.group = .structural
        }
        view.propertyOrder.removeAll { $0 == propertyID }
        view.hiddenProperties.removeAll { $0 == propertyID }
        view.columnWidths?.removeValue(forKey: propertyID)
    }

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
        return (resolved + [modified]).filter { $0.id != ReservedPropertyID.cover }
    }
}
