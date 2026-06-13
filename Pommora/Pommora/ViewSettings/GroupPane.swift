import SwiftUI

/// View Settings → Group — picks the active SavedView's `GroupConfig`.
///
/// Rows:
///   - **Default** — `group = .structural` (group by the natural container —
///     Collection / Set). Written as `.structural`; `nil` reads identically
///     through `GroupResolver`, so Default is the selected state when `group`
///     is absent.
///   - one row per groupable schema property (Select / Status / Checkbox) —
///     `.property(PropertyGrouping(propertyID:))`.
///   - **Remove Grouping** — `.flat` (no grouping).
///
/// Groupable candidates come from `ViewSettingsProperties.groupable` (shared
/// with the Filter pane); Cover and tiers never appear. Every read + write
/// resolves the active view by stable ID off the live `PageTypeManager` and
/// persists through `updateView` — mirrors `SortPane`.
struct GroupPane: View {
    let scope: ViewSettingsScope
    @Binding var path: [ViewSettingsRoute]

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(TierConfigManager.self) private var tierConfigManager
    @Environment(ActiveViewStore.self) private var activeViewStore

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
        let config = view.group
        let props = ViewSettingsProperties.groupable(
            scope: scope, manager: pageTypeManager, tierConfig: tierConfigManager.config)
        VStack(spacing: 0) {
            GroupRow(
                label: "Default",
                icon: "square.stack.3d.down.right",
                isSelected: isStructural(config),
                onSelect: { Task { await apply(.structural) } }
            )
            ForEach(props, id: \.id) { def in
                GroupRow(
                    label: def.name,
                    icon: def.displayIcon,
                    isSelected: isProperty(config, def.id),
                    onSelect: { Task { await apply(.property(PropertyGrouping(propertyID: def.id, order: nil))) } }
                )
            }
            GroupRow(
                label: "Remove Grouping",
                icon: "rectangle.grid.1x2",
                isSelected: isFlat(config),
                onSelect: { Task { await apply(.flat) } }
            )
            if let err = commitError {
                Text(err)
                    .font(PUI.Typography.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, PUI.Row.paddingHorizontal)
                    .padding(.vertical, PUI.Row.paddingVertical)
            }
        }
    }

    // MARK: - Selection predicates

    /// Default = `.structural` OR absent (`nil` resolves identically).
    private func isStructural(_ config: GroupConfig?) -> Bool {
        switch config {
        case .none, .some(.structural): return true
        default: return false
        }
    }

    private func isProperty(_ config: GroupConfig?, _ propertyID: String) -> Bool {
        if case .some(.property(let grouping)) = config { return grouping.propertyID == propertyID }
        return false
    }

    private func isFlat(_ config: GroupConfig?) -> Bool {
        if case .some(.flat) = config { return true }
        return false
    }

    // MARK: - Commit

    private func apply(_ config: GroupConfig) async {
        guard let view = currentView(), let cid = containerID() else { return }
        let viewID = view.id
        do {
            try await pageTypeManager.updateView(viewID, in: cid) { v in
                v.group = config
            }
            commitError = nil
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    // MARK: - Lookups (re-query live off the manager by stable ID)

    /// Resolves the ACTIVE view via the shared resolver, so the pane edits
    /// whichever view the user is currently viewing rather than the container's
    /// first view.
    private func currentView() -> SavedView? {
        guard let cid = containerID() else { return nil }
        return activeViewStore.resolvedActiveView(in: cid, manager: pageTypeManager)
    }

    private func containerID() -> String? {
        switch scope {
        case .pageType(let t): return t.id
        case .pageCollection(let c): return c.id
        default: return nil
        }
    }
}

// MARK: - GroupRow

private struct GroupRow: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: PUI.Row.interSpacing) {
                Image(systemName: icon)
                    .font(PUI.Icon.leading)
                    .foregroundStyle(.primary)
                    .frame(width: PUI.Icon.leadingFrame)
                Text(label)
                    .font(PUI.Typography.row)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(PUI.Icon.chevron)
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, PUI.Row.paddingHorizontal)
            .padding(.vertical, PUI.Row.paddingVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
