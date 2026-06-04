import SwiftUI

/// View Settings → Templates (ITEM scopes only).
///
/// Per-Type / per-Set template editor. T5.2 ships the archetype picker: the
/// layout roster renders as a selectable list, every archetype without a real
/// recipe is muted (single-sourced from `ItemWindowLayouts.hasRecipe`), and
/// selecting an enabled archetype persists `template_config.layout` to the
/// scope's own container (Type id for `.itemType`, Collection id for
/// `.itemCollection` — Collection scope overrides only the Collection, LD-10).
///
/// The route is payload-free — the pane derives its container from its own
/// `scope` (mirrors PropertyVisibilityPane's `containerID()` / `side` pattern),
/// so the route never carries an entity. All reads re-query the live manager by
/// stable ID; reading the scope snapshot would render stale after a write.
///
/// Human labels live HERE (`label(for:)`) — per-Nexus renaming is a view
/// concern, kept out of the schema enum. The `ItemWindowRenderer` mockup frame
/// (T5.3) + Type-vs-Collection scope affordance (T5.4) fill in later.
///
/// Chrome routed through shared `ViewSettingsPane` + `PaneHeader` + `PUI` tokens.
struct ItemTemplatePane: View {
    let scope: ViewSettingsScope
    @Binding var path: [ViewSettingsRoute]

    @Environment(ItemTypeManager.self) private var itemTypeManager

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
        // No ScrollView here — ViewSettingsPane owns the single scroll region.
        VStack(spacing: 0) {
            ForEach(LayoutArchetype.selectable, id: \.self) { archetype in
                ArchetypeRow(
                    label: ItemTemplatePane.label(for: archetype),
                    isSelected: archetype == currentLayout,
                    hasRecipe: ItemWindowLayouts.hasRecipe(for: archetype),
                    onSelect: { select(archetype) }
                )
            }
        }
    }

    // MARK: - Human labels
    //
    // Per-Nexus renaming is a view concern — labels stay OUT of the schema enum.

    /// Display name for an archetype in the picker. Static so the pure mapping
    /// is unit-testable without a SwiftUI host.
    static func label(for archetype: LayoutArchetype) -> String {
        switch archetype {
        case .compact: return "Compact Stack"
        case .standard: return "Standard Panel"
        case .bannerTwoColumn: return "Banner / Two-Column"
        case .gallery: return "Gallery"
        case .wide: return "Wide"
        case .reserved: return "Reserved"
        case .unknown(let s): return s
        }
    }

    // MARK: - Current selection

    /// The scope's effective layout, defaulting to `.standard` when nil (callers
    /// read `effective(...).layout ?? .standard`). Reads live from the manager by
    /// the scope-resolved id; the scope snapshot would render stale after a write.
    private var currentLayout: LayoutArchetype {
        guard let cid = containerID() else { return .standard }
        if let t = itemTypeManager.types.first(where: { $0.id == cid }) {
            return t.templateConfig?.layout ?? .standard
        }
        for cols in itemTypeManager.itemCollectionsByType.values {
            if let c = cols.first(where: { $0.id == cid }) {
                return c.templateConfig?.layout ?? .standard
            }
        }
        return .standard
    }

    // MARK: - Commit

    /// Persists the chosen archetype to the scope's own container's
    /// `template_config.layout`. Collection scope writes to the Collection id so
    /// the override stays Collection-local (LD-10); Type scope writes to the Type
    /// id. Muted archetypes never reach here (the row is `.disabled`).
    private func select(_ archetype: LayoutArchetype) {
        guard let target = containerID() else { return }
        Task {
            try? await itemTypeManager.updateTemplateConfig(in: target) { config in
                config.layout = archetype
            }
        }
    }

    // MARK: - Scope lookups
    //
    // Mirror PropertyVisibilityPane: extract the stable container ID once from
    // the scope, then re-query the live manager for every read. ITEM scopes only
    // — the row that routes here is gated on `.items` in StorageMenuRoot. The
    // scope-resolved id IS the write target (Type id for `.itemType`, Collection
    // id for `.itemCollection`) so a Collection edit overrides only the
    // Collection (LD-10); the Type-vs-Collection affordance lands in T5.4.

    private func containerID() -> String? {
        switch scope {
        case .itemType(let t): return t.id
        case .itemCollection(let c): return c.id
        default: return nil
        }
    }
}

// MARK: - ArchetypeRow

/// One archetype row: label + a selected indicator when it's the current layout.
/// Muted (tertiary + `.disabled`) when the archetype has no real recipe yet —
/// the single mute source is `ItemWindowLayouts.hasRecipe`, passed in as a Bool.
private struct ArchetypeRow: View {
    let label: String
    let isSelected: Bool
    let hasRecipe: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: PUI.Row.interSpacing) {
                Text(label)
                    .font(PUI.Typography.row)
                    .foregroundStyle(hasRecipe ? .primary : .tertiary)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(PUI.Icon.visibility)
                        .foregroundStyle(hasRecipe ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                }
            }
            .padding(.horizontal, PUI.Row.paddingHorizontal)
            .padding(.vertical, PUI.Row.paddingVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasRecipe)
    }
}

#if DEBUG
    #Preview("ItemTemplatePane — ItemType scope") {
        ItemTemplatePane(
            scope: .itemType(
                ItemType(
                    id: "01HIT", title: "Tasks", icon: "checklist",
                    properties: [], views: [], modifiedAt: Date()
                )
            ),
            path: .constant([.itemTemplate])
        )
    }
#endif
