import SwiftUI

/// Scope-aware context-link value picker — a chromeless liquid-glass dropdown styled
/// like a native macOS menu. Data-driven via `IndexQuery.entitiesByContextTargetGrouped`:
/// `.pageType` scopes show Collection rows that pop out a member panel
/// to the side (macOS-submenu style) with loose pages below an inset
/// divider; every other scope (tiers, agenda) renders a flat list (no submenu).
///
/// Relations are always multi-pick: selections accumulate; tapping a selected entity
/// removes it. Selecting does not dismiss the picker — the host popover dismisses on
/// click-away / Esc. A nil `index` renders an empty-state placeholder without crashing.
///
/// Each panel keeps a fixed width and a content-hugging height clamped between a
/// 5-row floor and a compact cap; it scrolls once rows overflow the cap. The floor
/// doubles as the anti-collapse guard (the `9deb818` fix): the popover only ever
/// grows from the floor, never collapsing before the list loads.
struct ContextPicker: View {
    @Binding var selectedIDs: [String]
    let scope: PropertyDefinition.RelationTarget
    let index: PommoraIndex?
    let onSelect: ([String]) -> Void

    @State private var grouped: GroupedEntities = .init(groups: [], rootEntities: [])
    @State private var activeGroupID: String?
    @State private var isLoading = false

    // Fixed width; height hugs content between a 5-row floor and a compact cap. The
    // floor is also the anti-collapse guard — the panel only grows from it, so the
    // chromeless popover can't collapse before the list loads.
    private static let panelWidth: CGFloat = 160
    private static let panelMinHeight: CGFloat = 170  // ≈ 5 callout rows
    private static let panelMaxHeight: CGFloat = 240  // compact cap; scrolls past

    var body: some View {
        HStack(alignment: .top, spacing: PUI.Spacing.md) {
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
                VStack(alignment: .leading, spacing: PUI.Spacing.md) {
                    ForEach(grouped.groups, id: \.container.id) { group in
                        ContextCollectionRow(
                            icon: group.container.icon,
                            title: group.container.title.isEmpty ? "Untitled" : group.container.title,
                            isActive: isActiveGroup(group)
                        ) {
                            activeGroupID = isActiveGroup(group) ? nil : group.container.id
                        }
                    }
                    if !grouped.groups.isEmpty && !grouped.rootEntities.isEmpty {
                        Divider().padding(.horizontal, PUI.Spacing.sm)  // inset to align with row content
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
                VStack(alignment: .leading, spacing: PUI.Spacing.md) {
                    ForEach(group.members, id: \.id) { entity in
                        leafRow(entity)
                    }
                }
            }
        }
    }

    /// Shared panel chrome: fixed width, content-hugging height (5-row floor → 2:3
    /// cap → scroll), 8pt padding, liquid-glass.
    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        SizedPanel(
            width: Self.panelWidth,
            minHeight: Self.panelMinHeight,
            maxHeight: Self.panelMaxHeight,
            content: content
        )
    }

    private func leafRow(_ entity: EntityRef) -> some View {
        ContextLeafRow(
            icon: entity.icon ?? ContextDisplayResolver.defaultIcon(for: entity.kind),
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
            grouped = try await IndexQuery(idx).entitiesByContextTargetGrouped(scope)
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
private struct ContextCollectionRow: View {
    let icon: String?
    let title: String
    let isActive: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: PUI.Spacing.sm) {
                Image(systemName: icon ?? "folder").foregroundStyle(.secondary)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .contentShape(Rectangle())
            .padding(.horizontal, PUI.Spacing.sm)
            .padding(.vertical, PUI.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: PUI.Radius.card, style: .continuous)
                    .fill(rowFill)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var rowFill: Color {
        if isActive { return Color.primary.opacity(0.10) }
        return PUI.Fill.hover(isHovered)
    }
}

/// A leaf row (Page / Context): icon + title + a trailing accent checkmark
/// rendered only on selected rows. An unselected row gives its full width to the
/// title (no reserved checkbox column); on selection the checkmark materializes at the
/// trailing edge and the title fills right up to it. The whole row toggles selection.
private struct ContextLeafRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: PUI.Spacing.sm) {
                Image(systemName: icon).foregroundStyle(.secondary)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    SelectionCheckmark()
                }
            }
            .font(.callout)
            .contentShape(Rectangle())
            .padding(.horizontal, PUI.Spacing.sm)
            .padding(.vertical, PUI.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: PUI.Radius.card, style: .continuous)
                    .fill(PUI.Fill.hover(isHovered))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Sized panel (fixed width, content-hugging height with floor + cap)

/// A fixed-width dropdown panel whose height hugs its content between a `minHeight`
/// floor (also the anti-collapse guard) and a `maxHeight` cap, scrolling once content
/// exceeds the cap. Height is driven from the measured content height via
/// `onGeometryChange`; the content's height is independent of the panel frame, so
/// there is no layout feedback loop. Each instance owns its own height, so the main
/// panel and the side member panel size independently.
private struct SizedPanel<Content: View>: View {
    let width: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let content: Content
    @State private var contentHeight: CGFloat = 0

    init(
        width: CGFloat,
        minHeight: CGFloat,
        maxHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.width = width
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PUI.Spacing.md)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    contentHeight = newHeight
                }
        }
        .frame(
            width: width,
            height: min(max(contentHeight, minHeight), maxHeight),
            alignment: .top
        )
        .chipDropdownPanel()
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
