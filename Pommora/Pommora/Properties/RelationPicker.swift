import SwiftUI

/// Scope-aware relation value picker — a chromeless liquid-glass dropdown styled
/// like a native macOS menu. Data-driven via `IndexQuery.entitiesByTargetGrouped`:
/// `.pageType` / `.itemType` scopes show Collection/Set rows that pop out a member
/// panel to the side (macOS-submenu style) with loose pages/items below an inset
/// divider; every other scope (tiers, agenda) renders a flat list (no submenu).
///
/// Relations are always multi-pick: selections accumulate; tapping a selected entity
/// removes it. Selecting does not dismiss the picker — the host popover dismisses on
/// click-away / Esc. A nil `index` renders an empty-state placeholder without crashing.
///
/// Sizing is a fixed 2:4 (w:h ≈ 1:2) per panel so the chromeless popover establishes
/// a stable size on first render and can't collapse before the candidate list loads
/// (the `9deb818` fix); each panel scrolls when its rows overflow.
struct RelationPicker: View {
    @Binding var selectedIDs: [String]
    let scope: PropertyDefinition.RelationTarget
    let index: PommoraIndex?
    let onSelect: ([String]) -> Void

    @State private var grouped: GroupedEntities = .init(groups: [], rootEntities: [])
    @State private var activeGroupID: String?
    @State private var isLoading = false

    // Proportional placeholders (2:4 ≈ 1:2), tuned to Body type. Fixed so the
    // chromeless popover never collapses; the panel scrolls past this height.
    private static let panelWidth: CGFloat = 160
    private static let panelHeight: CGFloat = 320

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            mainPanel
            if let active = activeGroup {
                memberPanel(active)
            }
        }
        .task { await loadGrouped() }
    }

    // MARK: - Panels

    private var mainPanel: some View {
        panel {
            if index == nil {
                placeholder("No index available")
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else if grouped.groups.isEmpty && grouped.rootEntities.isEmpty {
                placeholder("No matching items")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(grouped.groups, id: \.container.id) { group in
                        RelationCollectionRow(
                            icon: group.container.icon,
                            title: group.container.title.isEmpty ? "Untitled" : group.container.title,
                            isActive: isActiveGroup(group)
                        ) {
                            activeGroupID = isActiveGroup(group) ? nil : group.container.id
                        }
                    }
                    if !grouped.groups.isEmpty && !grouped.rootEntities.isEmpty {
                        Divider().padding(.horizontal, 6)  // inset to align with row content
                    }
                    ForEach(grouped.rootEntities, id: \.id) { entity in
                        leafRow(entity)
                    }
                }
            }
        }
    }

    private func memberPanel(_ group: EntityGroup) -> some View {
        panel {
            if group.members.isEmpty {
                placeholder("Empty")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(group.members, id: \.id) { entity in
                        leafRow(entity)
                    }
                }
            }
        }
    }

    /// Shared panel chrome: a fixed 2:4 frame, scrollable, 8pt padding, liquid-glass.
    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(width: Self.panelWidth, height: Self.panelHeight)
        .chipDropdownPanel()
    }

    private func leafRow(_ entity: EntityRef) -> some View {
        RelationLeafRow(
            icon: entity.icon ?? RelationDisplayResolver.defaultIcon(for: entity.kind),
            title: entity.title.isEmpty ? "Untitled" : entity.title,
            isSelected: selectedIDs.containsID(entity.id)
        ) {
            let wasSelected = selectedIDs.containsID(entity.id)
            let updated = computeSelection(id: entity.id, wasSelected: wasSelected, current: selectedIDs)
            selectedIDs = updated
            onSelect(updated)
        }
    }

    private func placeholder(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    // MARK: - Active-group helpers (plain, non-@ViewBuilder — keeps GRDB's String `==`
    // overload out of the view body; quirk #13)

    private var activeGroup: EntityGroup? {
        grouped.groups.first(where: { $0.container.id == activeGroupID })
    }

    private func isActiveGroup(_ group: EntityGroup) -> Bool {
        activeGroupID == group.container.id
    }

    // MARK: - Selection logic

    /// Pure selection computation — toggles `id` in the current selection. Relations
    /// are always multi-pick. Non-private so tests call it without a live button tap.
    func computeSelection(id: String, wasSelected: Bool, current: [String]) -> [String] {
        wasSelected ? current.filter { $0 != id } : current + [id]
    }

    // MARK: - Data loading

    private func loadGrouped() async {
        guard let idx = index else { return }
        isLoading = true
        do {
            grouped = try await IndexQuery(idx).entitiesByTargetGrouped(scope)
        } catch {
            grouped = .init(groups: [], rootEntities: [])
        }
        isLoading = false
    }
}

// MARK: - Rows (plain value types — isolated from GRDB String overloads, quirk #13)

/// A Collection/Set row: the container's icon (or a folder glyph fallback) + title
/// + trailing chevron. The whole row is the drill button — tapping pops out (or
/// closes) that collection's member panel.
private struct RelationCollectionRow: View {
    let icon: String?
    let title: String
    let isActive: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: icon ?? "folder").foregroundStyle(.secondary)
                Text(title).font(.body)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowFill)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var rowFill: Color {
        if isActive { return Color.primary.opacity(0.10) }
        return isHovered ? Color.primary.opacity(0.06) : Color.clear
    }
}

/// A leaf row (Page / Item / Context): icon + title + a selection checkmark shown
/// only when selected. The whole row toggles selection.
private struct RelationLeafRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(.secondary)
                Text(title).font(.body)
                Spacer(minLength: 0)
                SelectionCheckmark(isSelected: isSelected)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - [String] containsID helper

extension Array where Element == String {
    /// Avoids GRDB's `SQLSpecificExpressible`-based `contains` overload by
    /// explicitly using `first(where:)` with a closure comparison.
    fileprivate func containsID(_ id: String) -> Bool {
        first(where: { element in element == id }) != nil
    }
}
