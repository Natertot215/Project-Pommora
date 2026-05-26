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

    @State private var commitError: String?

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(path: $path, title: "Property Visibility")
            content
        }
        .frame(width: PUI.Pane.width, height: PUI.Pane.height)
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

        ScrollView {
            VStack(spacing: 0) {
                ForEach(visibleOrdered + unaccountedOrdered, id: \.id) { def in
                    PropertyVisibilityRow(
                        definition: def,
                        isVisible: !hiddenSet.contains(def.id),
                        onToggle: { Task { await toggle(def.id, currentlyVisible: !hiddenSet.contains(def.id)) } }
                    )
                }
                ForEach(hiddenOrdered, id: \.id) { def in
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
    }

    // MARK: - Lookups

    private func currentView() -> SavedView? {
        switch scope {
        case .pageType(let t):
            return t.views.first
        case .itemType(let t):
            return t.views.first
        case .pageCollection(let c):
            return c.views.first
        case .itemCollection(let c):
            return c.views.first
        default:
            return nil
        }
    }

    private func parentTypeProperties() -> [PropertyDefinition] {
        switch scope {
        case .pageType(let t):
            return t.properties
        case .itemType(let t):
            return t.properties
        case .pageCollection(let c):
            return pageTypeManager.types.first(where: { $0.id == c.typeID })?.properties ?? []
        case .itemCollection(let c):
            return itemTypeManager.types.first(where: { $0.id == c.typeID })?.properties ?? []
        default:
            return []
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
            commitError = String(describing: error)
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
