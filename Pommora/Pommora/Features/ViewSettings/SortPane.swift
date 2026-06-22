import SwiftUI

/// View Settings → Sort — picks the single active sort criterion for the
/// container's active SavedView.
///
/// The field is `[SortCriterion]?` (multi-criterion lands later); the UI
/// restricts to ONE criterion — every selection REPLACES `sort` with a
/// single-element array, and **Manual** writes `sort = nil`. The table's
/// manual-drag affordances render only when `sort == nil`, so picking Manual
/// is what re-enables drag reordering.
///
/// Rows:
///   - **Manual** — `sort = nil` (drag-to-order mode)
///   - **Title A→Z / Z→A** — `_title` ascending / descending
///   - **Created** — `_id` ascending (ULIDs are creation-ordered)
///   - **Recent** — `_modified_at` descending
///   - one row per sortable schema property, offering asc + desc
///
/// Persistence mirrors the other panes: writes through
/// `PageTypeManager.updateView(_:in:transform:)` against the active view
/// resolved by stable ID (re-queried live off the manager, never the stale
/// `ViewSettingsScope` snapshot).
struct SortPane: View {
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
        let active = view.sort?.first
        VStack(spacing: 0) {
            ForEach(SortPreset.allCases) { preset in
                SortRow(
                    label: preset.label,
                    icon: preset.icon,
                    isSelected: preset.matches(active),
                    onSelect: { Task { await apply(preset.criterion) } }
                )
            }
            ForEach(sortableProperties(), id: \.id) { def in
                SortRow(
                    label: "\(def.name) (A→Z)",
                    icon: def.displayIcon,
                    isSelected: matches(active, def.id, .ascending),
                    onSelect: {
                        Task { await apply(SortCriterion(propertyID: def.id, direction: .ascending)) }
                    }
                )
                SortRow(
                    label: "\(def.name) (Z→A)",
                    icon: def.displayIcon,
                    isSelected: matches(active, def.id, .descending),
                    onSelect: {
                        Task { await apply(SortCriterion(propertyID: def.id, direction: .descending)) }
                    }
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

    private func matches(_ active: SortCriterion?, _ propertyID: String, _ direction: SortDirection) -> Bool {
        active?.propertyID == propertyID && active?.direction == direction
    }

    // MARK: - Commit

    /// Writes `criterion` as the single active sort (or clears it for Manual).
    private func apply(_ criterion: SortCriterion?) async {
        guard let view = currentView(), let cid = containerID() else { return }
        let viewID = view.id
        do {
            try await pageTypeManager.updateView(viewID, in: cid) { v in
                v.sort = criterion.map { [$0] }
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

    /// User-defined sortable properties (Relation + file columns excluded —
    /// they have no meaningful ordering). Reserved columns are surfaced via the
    /// fixed presets, so they're filtered out here.
    private func sortableProperties() -> [PropertyDefinition] {
        guard let typeID = parentTypeID() else { return [] }
        let schema: [PropertyDefinition] =
            pageTypeManager.types.first(where: { $0.id == typeID })?
            .resolvedProperties(tierConfig: tierConfigManager.config) ?? []
        return schema.filter { def in
            !ReservedPropertyID.isReserved(def.id) && def.type.isSortable
        }
    }

    private func containerID() -> String? { scope.containerID }

    private func parentTypeID() -> String? { scope.schemaTypeID }
}

// MARK: - SortPreset

/// The fixed sort rows shown above per-property options. Each maps to a
/// concrete `SortCriterion` (or `nil` for Manual). Modeled as an enum + switch
/// so every preset is compiler-enforced (HARD RULE).
private enum SortPreset: String, CaseIterable, Identifiable {
    case manual
    case titleAscending
    case titleDescending
    case created
    case recent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .titleAscending: return "Title A→Z"
        case .titleDescending: return "Title Z→A"
        case .created: return "Created"
        case .recent: return "Recent"
        }
    }

    var icon: String {
        switch self {
        case .manual: return "hand.draw"
        case .titleAscending: return "textformat.abc"
        case .titleDescending: return "textformat.abc"
        case .created: return "calendar.badge.plus"
        case .recent: return "clock.arrow.circlepath"
        }
    }

    /// `nil` for Manual (clears `sort`); otherwise the single criterion this
    /// preset persists.
    var criterion: SortCriterion? {
        switch self {
        case .manual: return nil
        case .titleAscending: return SortCriterion(propertyID: ReservedPropertyID.title, direction: .ascending)
        case .titleDescending: return SortCriterion(propertyID: ReservedPropertyID.title, direction: .descending)
        case .created: return SortCriterion(propertyID: ReservedPropertyID.id, direction: .ascending)
        case .recent: return SortCriterion(propertyID: ReservedPropertyID.modifiedAt, direction: .descending)
        }
    }

    /// True iff `active` is the criterion this preset writes (Manual matches a
    /// nil sort).
    func matches(_ active: SortCriterion?) -> Bool {
        criterion == active
    }
}

// MARK: - SortRow

private struct SortRow: View {
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
