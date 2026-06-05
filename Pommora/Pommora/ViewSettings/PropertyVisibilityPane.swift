import SwiftUI

/// View Settings → Property Visibility — toggle which properties show as
/// columns in the active view + drag-reorder them.
///
/// Click any non-reserved row → flips between visible (solid) and hidden
/// (strikethrough + tertiary color). Drag handle reorders the visible
/// section. `_modified_at` (Last Edited Time) is locked-always-visible per
/// locked decision (toggling it off causes UX confusion since it's the
/// default sort criterion).
///
/// Persistence: writes the active SavedView's `visibleProperties` +
/// `hiddenProperties` arrays atomically via the manager's
/// `updateView(_:in:transform:)`. The active SavedView is the container's
/// `views[0]` at v0.3.1 (single-view-per-container; multi-saved-view +
/// view-tabs land at v0.5.0).
///
/// Container lookup: PageType/ItemType scopes write to the Type's
/// `views[0]`; Collection scopes write to the Collection's own `views[0]`
/// (locked: each Collection's view is INDEPENDENT of the parent Type's).
///
/// Chrome routed through shared `PaneHeader` + `PUI` tokens.
struct PropertyVisibilityPane: View {
    let scope: ViewSettingsScope
    @Binding var path: [ViewSettingsRoute]

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(TierConfigManager.self) private var tierConfigManager

    @State private var commitError: String?

    var body: some View {
        ViewSettingsPane {
            PaneHeader(path: $path)
        } content: {
            content
        }
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if let view = currentView() {
            rows(for: view)
        } else {
            ContentUnavailableView(
                "No view configured",
                systemImage: "rectangle.and.text.magnifyingglass",
                description: Text("loadAll should have minted a default Table view; reopen the popover.")
            )
        }
    }

    @ViewBuilder
    private func rows(for view: SavedView) -> some View {
        let schemaProps = parentTypeProperties()
        // Materialize the rendering order: visible first (in the view's
        // explicit order), then hidden (in schema-declaration order).
        let visibleOrdered = view.visibleProperties.compactMap { id in
            schemaProps.first(where: { $0.id == id })
        }
        let hiddenSet = Set(view.hiddenProperties)
        let hiddenOrdered = schemaProps.filter { hiddenSet.contains($0.id) }
        let unaccountedOrdered = schemaProps.filter {
            !view.visibleProperties.contains($0.id) && !hiddenSet.contains($0.id)
        }
        // The reorderable section: visible + unaccounted (rendered as
        // visible per the existing logic). Dragging amongst these rewrites
        // visibleProperties to reflect the new order; any unaccounted
        // property dragged here gets implicitly added to visibleProperties.
        let reorderable = visibleOrdered + unaccountedOrdered

        // No ScrollView here — ViewSettingsPane owns the single scroll region.
        VStack(spacing: 0) {
            ForEach(reorderable, id: \.id) { def in
                PropertyVisibilityRow(
                    definition: def,
                    isVisible: !hiddenSet.contains(def.id),
                    onToggle: { Task { await toggle(def.id, currentlyVisible: !hiddenSet.contains(def.id)) } }
                )
                .draggable(def.id)
                .dropDestination(for: String.self) { droppedIDs, _ in
                    guard let droppedID = droppedIDs.first else { return false }
                    return reorder(
                        currentOrder: reorderable.map(\.id),
                        droppedID: droppedID,
                        ontoTargetID: def.id
                    )
                }
            }
            ForEach(hiddenOrdered, id: \.id) { def in
                // Hidden rows are NOT draggable — drag-reorder is only
                // for the visible section. Tap-to-toggle still works.
                PropertyVisibilityRow(
                    definition: def,
                    isVisible: false,
                    onToggle: { Task { await toggle(def.id, currentlyVisible: false) } }
                )
            }
            if let err = commitError {
                Text(err)
                    .font(PUI.Typography.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, PUI.Row.paddingHorizontal)
                    .padding(.vertical, PUI.Row.paddingVertical)
            }
        }
    }

    /// Reorders the visible-section property IDs by moving `droppedID` to
    /// the position of `ontoTargetID`, then persists via `updateView`. The
    /// new order REPLACES `visibleProperties`; any property that wasn't in
    /// `visibleProperties` before but is now part of the reorder is
    /// implicitly added to visibleProperties (which is the intuitive UX
    /// when dragging an "unaccounted" row into a specific position).
    private func reorder(
        currentOrder: [String],
        droppedID: String,
        ontoTargetID: String
    ) -> Bool {
        let newOrder = PropertyIDReorder.move(currentOrder, moving: droppedID, onto: ontoTargetID)
        guard newOrder != currentOrder else { return false }

        guard let view = currentView(), let cid = containerID(), let side else { return false }
        let viewID = view.id
        Task {
            do {
                switch side {
                case .pages:
                    try await pageTypeManager.updateView(viewID, in: cid) { v in
                        v.visibleProperties = newOrder
                    }
                case .items:
                    try await itemTypeManager.updateView(viewID, in: cid) { v in
                        v.visibleProperties = newOrder
                    }
                }
                commitError = nil
            } catch {
                commitError = PropertyEditorErrorMessage.string(for: error)
            }
        }
        return true
    }

    // MARK: - Lookups
    //
    // All lookups read live from the manager via stable IDs. Reading from
    // the scope payload (`t.views`, `t.properties`, etc.) renders stale
    // state after any in-popover mutation since `ViewSettingsScope` carries
    // a snapshot. Extract the stable container ID + parent type ID once,
    // then re-query the manager for every read.

    private func currentView() -> SavedView? {
        guard let cid = containerID() else { return nil }
        switch side {
        case .pages:
            // Container can be either a PageType or a PageCollection.
            if let t = pageTypeManager.types.first(where: { $0.id == cid }) {
                return t.views.first
            }
            for cols in pageTypeManager.pageCollectionsByType.values {
                if let c = cols.first(where: { $0.id == cid }) { return c.views.first }
            }
            return nil
        case .items:
            if let t = itemTypeManager.types.first(where: { $0.id == cid }) {
                return t.views.first
            }
            for cols in itemTypeManager.itemCollectionsByType.values {
                if let c = cols.first(where: { $0.id == cid }) { return c.views.first }
            }
            return nil
        case .none:
            return nil
        }
    }

    /// Visible-in-pane properties: user-defined + the three tier relations +
    /// `_modified_at` (kept as the locked-always-visible default sort
    /// criterion). The remaining reserved IDs (`_id`, `_created_at`,
    /// `_status`) are filtered out — visibility is meaningless
    /// for system-managed columns. Tier columns are surfaced via
    /// `resolvedProperties` (the schema doesn't store them; they're merged in)
    /// so users can hide/show them like any other column.
    private func parentTypeProperties() -> [PropertyDefinition] {
        guard let typeID = parentTypeID() else { return [] }
        let schema: [PropertyDefinition]
        switch side {
        case .pages:
            schema = pageTypeManager.types.first(where: { $0.id == typeID })?
                .resolvedProperties(tierConfig: tierConfigManager.config) ?? []
        case .items:
            schema = itemTypeManager.types.first(where: { $0.id == typeID })?
                .resolvedProperties(tierConfig: tierConfigManager.config) ?? []
        case .none:
            return []
        }
        let surfaced: Set<String> = [
            ReservedPropertyID.modifiedAt,
            ReservedPropertyID.tier1,
            ReservedPropertyID.tier2,
            ReservedPropertyID.tier3,
        ]
        return schema.filter { def in
            !ReservedPropertyID.isReserved(def.id) || surfaced.contains(def.id)
        }
    }

    private func containerID() -> String? {
        switch scope {
        case .pageType(let t): return t.id
        case .itemType(let t): return t.id
        case .pageCollection(let c): return c.id
        case .itemCollection(let c): return c.id
        default: return nil
        }
    }

    private func parentTypeID() -> String? {
        switch scope {
        case .pageType(let t): return t.id
        case .itemType(let t): return t.id
        case .pageCollection(let c): return c.typeID
        case .itemCollection(let c): return c.typeID
        default: return nil
        }
    }

    private enum SideKind { case pages, items }
    private var side: SideKind? {
        switch scope {
        case .pageType, .pageCollection: return .pages
        case .itemType, .itemCollection: return .items
        default: return nil
        }
    }

    // MARK: - Commit

    private func toggle(_ propertyID: String, currentlyVisible: Bool) async {
        // _modified_at always visible — locked decision.
        guard propertyID != "_modified_at" else { return }
        guard let view = currentView(), let cid = containerID(), let side else { return }
        let viewID = view.id

        do {
            switch side {
            case .pages:
                try await pageTypeManager.updateView(viewID, in: cid) { v in
                    PropertyVisibilityPane.applyToggle(&v, propertyID: propertyID, currentlyVisible: currentlyVisible)
                }
            case .items:
                try await itemTypeManager.updateView(viewID, in: cid) { v in
                    PropertyVisibilityPane.applyToggle(&v, propertyID: propertyID, currentlyVisible: currentlyVisible)
                }
            }
            commitError = nil
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    /// Move propertyID between visibleProperties + hiddenProperties.
    /// When making visible: append to visibleProperties end, remove from hidden.
    /// When making hidden: remove from visibleProperties, append to hidden.
    static func applyToggle(_ view: inout SavedView, propertyID: String, currentlyVisible: Bool) {
        if currentlyVisible {
            view.visibleProperties.removeAll { $0 == propertyID }
            if !view.hiddenProperties.contains(propertyID) {
                view.hiddenProperties.append(propertyID)
            }
        } else {
            view.hiddenProperties.removeAll { $0 == propertyID }
            if !view.visibleProperties.contains(propertyID) {
                view.visibleProperties.append(propertyID)
            }
        }
    }
}

// MARK: - PropertyVisibilityRow

private struct PropertyVisibilityRow: View {
    let definition: PropertyDefinition
    let isVisible: Bool
    let onToggle: () -> Void

    private var isModifiedAt: Bool {
        definition.id == "_modified_at"
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: PUI.Row.interSpacing) {
                Image(systemName: definition.icon ?? definition.type.pickerIcon)
                    .font(PUI.Icon.leading)
                    .foregroundStyle(isVisible ? .primary : .tertiary)
                    .frame(width: PUI.Icon.leadingFrame)

                Text(definition.name)
                    .font(PUI.Typography.row)
                    .foregroundStyle(isVisible ? .primary : .tertiary)
                    .strikethrough(!isVisible, color: .secondary)
                    .lineLimit(1)

                Spacer()

                if isModifiedAt {
                    Image(systemName: "lock.fill")
                        .font(PUI.Icon.lock)
                        .foregroundStyle(.tertiary)
                        .help("Always visible — default sort criterion")
                } else {
                    Image(systemName: isVisible ? "eye" : "eye.slash")
                        .font(PUI.Icon.visibility)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, PUI.Row.paddingHorizontal)
            .padding(.vertical, PUI.Row.paddingVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isModifiedAt)
    }
}
