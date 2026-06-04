import SwiftUI

/// View Settings → Templates (ITEM scopes only).
///
/// Per-Type / per-Set template editor. Three stacked surfaces:
///   • the archetype picker (T5.2) — `template_config.layout`;
///   • the WYSIWYG mockup frame (T5.3) — an embedded `ItemWindowRenderer(editing:
///     true)` that draws the governed Item and carries the pin/unpin + drag-
///     reorder affordances for `template_config.promoted_properties` (built in
///     T3.5; this pane only EMBEDS it);
///   • the per-property `display` + cover pickers (T5.3) — small menus writing
///     `promoted_properties[].display` and `cover_property_id`.
///
/// All template writes go through `ItemTypeManager.updateTemplateConfig` (the
/// single template-persist path). On the first write that establishes a
/// Collection's `promoted_properties` the pane also clears that Collection's
/// legacy `pinnedProperties` so the resolver collapses to one source.
///
/// The route is payload-free — the pane derives its container from its own
/// `scope` (mirrors PropertyVisibilityPane's `containerID()` / `side` pattern),
/// so the route never carries an entity. All reads re-query the live manager by
/// stable ID; reading the scope snapshot would render stale after a write.
///
/// Human labels live HERE (`label(for:)`) — per-Nexus renaming is a view
/// concern, kept out of the schema enum.
///
/// Chrome routed through shared `ViewSettingsPane` + `PaneHeader` + `PUI` tokens.
struct ItemTemplatePane: View {
    let scope: ViewSettingsScope
    @Binding var path: [ViewSettingsRoute]

    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(ItemContentManager.self) private var itemContentManager

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
        VStack(alignment: .leading, spacing: PUI.Spacing.xl) {
            archetypeSection
            if let resolved = resolvedScope {
                Divider()
                mockupSection(resolved)
                Divider()
                coverSection(resolved)
                if !promotedEntries(resolved).isEmpty {
                    Divider()
                    displaySection(resolved)
                }
            }
        }
    }

    // MARK: - Archetype picker (T5.2)

    private var archetypeSection: some View {
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

    // MARK: - Mockup item frame (T5.3)
    //
    // The WYSIWYG surface: an `ItemWindowRenderer` in edit mode. Pin/unpin +
    // drag-reorder come FROM the renderer (T3.5) — this pane only embeds it,
    // targeting the scope's own container so a Collection edit overrides only
    // the Collection (LD-10). Hosted in a fixed-size framed container so the
    // mockup reads as "the item it governs" without swallowing the popover.

    @ViewBuilder
    private func mockupSection(_ resolved: ResolvedScope) -> some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.sm) {
            sectionLabel("Layout preview")
            ItemWindowRenderer(
                item: resolved.representativeItem,
                template: TemplateResolver.effective(
                    type: resolved.type, collection: resolved.collection),
                itemType: resolved.type,
                collection: resolved.collection,
                editing: true,
                templateContainerID: containerID()
            )
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: PUI.Radius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: PUI.Radius.medium)
                    .strokeBorder(.quaternary)
            )
        }
    }

    // MARK: - Cover picker (T5.3)

    @ViewBuilder
    private func coverSection(_ resolved: ResolvedScope) -> some View {
        let eligible = Self.coverEligible(resolved.type.properties)
        VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
            sectionLabel("Cover image")
            if eligible.isEmpty {
                Text("No image file properties on this Type.")
                    .font(PUI.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, PUI.Row.paddingHorizontal)
            } else {
                CoverPickerRow(
                    eligible: eligible,
                    selectedID: currentCoverID,
                    onSelect: { setCover($0) }
                )
            }
        }
    }

    // MARK: - Per-property display pickers (T5.3)

    @ViewBuilder
    private func displaySection(_ resolved: ResolvedScope) -> some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
            sectionLabel("Promoted property display")
            ForEach(promotedEntries(resolved), id: \.promotion.id) { entry in
                DisplayPickerRow(
                    name: entry.definition.name,
                    icon: entry.definition.icon ?? entry.definition.type.pickerIcon,
                    selected: entry.promotion.display,
                    onSelect: { setDisplay($0, for: entry.promotion.id) }
                )
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(PUI.Typography.sectionHeader)
            .foregroundStyle(.secondary)
            .padding(.horizontal, PUI.Row.paddingHorizontal)
    }

    // MARK: - Pure helpers (unit-testable without a SwiftUI host)
    //
    // Pure value code OUTSIDE any `@ViewBuilder` body, so `Array`/`String`
    // collection methods stay free of the GRDB String-overload ambiguity (quirk
    // #12) and the helpers are testable without bootstrapping a view.

    /// The Type's properties eligible to be a template cover: `.file` properties
    /// whose `accept` admits an image MIME (`image/*` or a concrete `image/...`).
    /// Input order preserved.
    static func coverEligible(_ defs: [PropertyDefinition]) -> [PropertyDefinition] {
        defs.filter(isCoverEligible)
    }

    /// True when a single property may serve as a template cover: a `.file`
    /// property with at least one image entry in its `accept` whitelist. Uses
    /// `first(where:)` (quirk #12) instead of `contains` over the accept list.
    static func isCoverEligible(_ def: PropertyDefinition) -> Bool {
        guard def.type == .file, let accept = def.accept else { return false }
        return accept.first(where: Self.isImageAccept) != nil
    }

    /// Whether an `accept` pattern names an image MIME — the wildcard `image/*`
    /// or any concrete `image/<subtype>`.
    private static func isImageAccept(_ pattern: String) -> Bool {
        pattern == "image/*" || pattern.hasPrefix("image/")
    }

    /// Returns a copy of `promoted` with the entry matching `id` set to `display`
    /// (preserving order and every other entry). No-op when `id` isn't present.
    static func applyDisplay(
        _ display: PropertyDisplay?, to id: String, in promoted: [PromotedProperty]
    ) -> [PromotedProperty] {
        promoted.map { entry in
            guard entry.id == id else { return entry }
            var updated = entry
            updated.display = display
            return updated
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

    // MARK: - Resolved scope (Type + optional Collection + representative Item)

    /// The Type, its optional Collection, and a representative Item for the
    /// embedded mockup. Bundled so the body resolves the scope once.
    struct ResolvedScope {
        let type: ItemType
        let collection: ItemCollection?
        let representativeItem: Item
    }

    /// Resolves the scope to its Type + optional Collection + a representative
    /// Item (real-first, else a minimal synthetic placeholder the edit-mode
    /// renderer fills with placeholder values). Re-queries the live managers by
    /// stable ID so it never renders stale after a write.
    private var resolvedScope: ResolvedScope? {
        switch scope {
        case .itemType(let t):
            guard let type = itemTypeManager.types.first(where: { $0.id == t.id }) else { return nil }
            let item = itemContentManager.items(in: type).first ?? Self.syntheticItem(title: type.title)
            return ResolvedScope(type: type, collection: nil, representativeItem: item)
        case .itemCollection(let c):
            guard let typeID = parentTypeID(),
                let type = itemTypeManager.types.first(where: { $0.id == typeID }),
                let collection = itemTypeManager.itemCollections(in: type).first(where: { $0.id == c.id })
            else { return nil }
            let item =
                itemContentManager.items(in: collection).first
                ?? Self.syntheticItem(title: collection.title)
            return ResolvedScope(type: type, collection: collection, representativeItem: item)
        default:
            return nil
        }
    }

    /// The promoted entries (definition + promotion config) for the resolved
    /// scope, in promoted order. Resolved through `TemplateResolver.promoted` so
    /// a legacy `pinnedProperties` Collection still surfaces rows before its
    /// first template write. Properties no longer in the schema are dropped.
    private func promotedEntries(
        _ resolved: ResolvedScope
    ) -> [(promotion: PromotedProperty, definition: PropertyDefinition)] {
        let promoted = TemplateResolver.promoted(type: resolved.type, collection: resolved.collection)
        return promoted.compactMap { promotion in
            guard let def = resolved.type.properties.first(where: { $0.id == promotion.id }) else {
                return nil
            }
            return (promotion, def)
        }
    }

    /// A minimal synthetic Item for a scope with zero members — a placeholder so
    /// the mockup "looks like the item it governs" even before any Item exists.
    /// The edit-mode renderer fills representative values per property type.
    private static func syntheticItem(title: String) -> Item {
        Item(
            id: "template-mockup",
            title: title,
            icon: nil,
            description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(),
            modifiedAt: Date()
        )
    }

    // MARK: - Current selection

    /// The scope's effective layout, defaulting to `.standard` when nil. Reads
    /// live from the manager by the scope-resolved id; the scope snapshot would
    /// render stale after a write.
    private var currentLayout: LayoutArchetype {
        liveTemplateConfig?.layout ?? .standard
    }

    /// The scope's effective cover property id (live read).
    private var currentCoverID: String? {
        liveTemplateConfig?.coverPropertyID
    }

    /// The live `template_config` for the scope's own container (Type or
    /// Collection id), re-queried from the manager so reads never go stale.
    private var liveTemplateConfig: ItemTemplateConfig? {
        guard let cid = containerID() else { return nil }
        if let t = itemTypeManager.types.first(where: { $0.id == cid }) {
            return t.templateConfig
        }
        for cols in itemTypeManager.itemCollectionsByType.values {
            if let c = cols.first(where: { $0.id == cid }) {
                return c.templateConfig
            }
        }
        return nil
    }

    // MARK: - Commit

    /// Persists the chosen archetype to the scope's own container's
    /// `template_config.layout`. Collection scope writes to the Collection id so
    /// the override stays Collection-local (LD-10). Muted archetypes never reach
    /// here (the row is `.disabled`).
    private func select(_ archetype: LayoutArchetype) {
        guard let target = containerID() else { return }
        Task {
            try? await itemTypeManager.updateTemplateConfig(in: target) { config in
                config.layout = archetype
            }
        }
    }

    /// Sets the cover property id (nil clears it). Single template-persist path.
    private func setCover(_ propertyID: String?) {
        guard let target = containerID() else { return }
        Task {
            try? await itemTypeManager.updateTemplateConfig(in: target) { config in
                config.coverPropertyID = propertyID
            }
        }
    }

    /// Sets a promoted property's per-property `display`. Seeds the promoted list
    /// from the resolver (so a legacy `pinnedProperties` Collection's pins become
    /// a real `promoted_properties` entry on the FIRST write here) via
    /// `applyDisplay`, persists through the single writer, and — for a Collection
    /// — clears the legacy `pinnedProperties` so the resolver has one source.
    private func setDisplay(_ display: PropertyDisplay?, for propertyID: String) {
        guard let resolved = resolvedScope, let target = containerID() else { return }
        let seeded = TemplateResolver.promoted(type: resolved.type, collection: resolved.collection)
        let updated = Self.applyDisplay(display, to: propertyID, in: seeded)
        let establishesPromoted = resolved.collection?.templateConfig?.promotedProperties == nil
        let collection = resolved.collection
        Task {
            try? await itemTypeManager.updateTemplateConfig(in: target) { config in
                config.promotedProperties = updated
            }
            // First write that establishes a Collection's promoted_properties:
            // collapse the legacy pinned_properties to empty so the resolver
            // (promoted-first) has a single source.
            if establishesPromoted, let collection {
                try? await itemTypeManager.updateItemCollectionPinnedProperties(collection, to: [])
            }
        }
    }

    // MARK: - Scope lookups
    //
    // Mirror PropertyVisibilityPane: extract the stable container ID once from
    // the scope, then re-query the live manager for every read. The scope-
    // resolved id IS the write target (Type id for `.itemType`, Collection id
    // for `.itemCollection`) so a Collection edit overrides only the Collection
    // (LD-10).

    private func containerID() -> String? {
        switch scope {
        case .itemType(let t): return t.id
        case .itemCollection(let c): return c.id
        default: return nil
        }
    }

    /// The parent ItemType id for a `.itemCollection` scope — read from the
    /// Collection's `typeID` (re-added after T5.2 removed it). Nil for other
    /// scopes.
    private func parentTypeID() -> String? {
        switch scope {
        case .itemCollection(let c): return c.typeID
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

// MARK: - CoverPickerRow

/// The cover picker: a `Menu` of the Type's image-file properties plus a "None"
/// option. Isolated as a plain value-typed sub-view (quirk #12 — keeps GRDB
/// String-overload pollution out of the parent's `@ViewBuilder`).
private struct CoverPickerRow: View {
    let eligible: [PropertyDefinition]
    let selectedID: String?
    let onSelect: (String?) -> Void

    private var selectedName: String {
        guard let selectedID, let def = eligible.first(where: { $0.id == selectedID }) else {
            return "None"
        }
        return def.name
    }

    var body: some View {
        HStack(spacing: PUI.Row.interSpacing) {
            Text("Cover")
                .font(PUI.Typography.row)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("None") { onSelect(nil) }
                Divider()
                ForEach(eligible) { def in
                    Button {
                        onSelect(def.id)
                    } label: {
                        Label(def.name, systemImage: def.icon ?? "photo")
                    }
                }
            } label: {
                Text(selectedName)
                    .font(PUI.Typography.row)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)
    }
}

// MARK: - DisplayPickerRow

/// One promoted property's display picker: a `Menu` listing every
/// `PropertyDisplay` mode plus "Default" (clears the override → archetype
/// default). Isolated as a plain value-typed sub-view (quirk #12).
private struct DisplayPickerRow: View {
    let name: String
    let icon: String
    let selected: PropertyDisplay?
    let onSelect: (PropertyDisplay?) -> Void

    /// The selectable display modes. `.unknown` is forward-compat only — never
    /// user-selectable — so it's omitted.
    private static let modes: [PropertyDisplay] = [.inline, .thumbnail, .banner, .chips, .list]

    private var selectedLabel: String {
        guard let selected else { return "Default" }
        return Self.label(for: selected)
    }

    private static func label(for display: PropertyDisplay) -> String {
        switch display {
        case .inline: return "Inline"
        case .thumbnail: return "Thumbnail"
        case .banner: return "Banner"
        case .chips: return "Chips"
        case .list: return "List"
        case .unknown(let s): return s
        }
    }

    var body: some View {
        HStack(spacing: PUI.Row.interSpacing) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(name)
                .font(PUI.Typography.row)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            Menu {
                Button("Default") { onSelect(nil) }
                Divider()
                ForEach(Self.modes, id: \.rawValue) { mode in
                    Button(Self.label(for: mode)) { onSelect(mode) }
                }
            } label: {
                Text(selectedLabel)
                    .font(PUI.Typography.row)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)
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
