import MarkdownPM
import SwiftUI

/// The single config-driven renderer that draws an Item Window. It serves two
/// surfaces via the `editing` flag:
///   • LIVE window (`editing == false`) — a clean DISPLAY-ONLY stub: icon + title
///     + read-only body + footer, nothing else. No editing surfaces, no save path.
///     This is the bedrock the zone-framework rework builds onto (it retires the
///     archetype machinery below); the live window curates nothing of its own.
///   • Templates-pane mockup (`editing == true`) — the full archetype layout
///     (promoted/overflow/relations regions, cover, drag-reorder + pin/unpin)
///     where a template's properties are arranged. Reworked into the zone
///     assigner in a later step.
///
/// The renderer is pure of CRUD/manager mutation on the live path — it only READS
/// the resolved `Item` + `ItemTemplateConfig` + schema. Edit-mode persists ONLY
/// `template_config` (pin/unpin + reorder), never Item values.
///
/// Context-link/tier display resolves through the shared `ContextDisplayResolver`
/// from the environment (the same instance every detail surface uses); the
/// resolver closure handed to `PropertyCellDisplay` is `{ contextDisplay.resolve($0) }`,
/// matching the detail-view call sites.
struct ItemWindowRenderer: View {
    let item: Item
    let template: ItemTemplateConfig
    let itemType: ItemType
    let collection: ItemCollection?

    /// Edit/mockup mode. When `true` the renderer is the WYSIWYG template-editing
    /// surface the Templates pane reuses: promoted rows gain drag-reorder + a
    /// pin/unpin "Add Property" affordance, both writing `template_config.
    /// promoted_properties`. When `false` (the LIVE window) the renderer is the
    /// display-only stub — no edit affordances, no value/title/icon editing, and
    /// `promoted_properties` is never mutated.
    var editing: Bool = false

    /// The container whose `template_config` edit-mode writes persist to. When
    /// `nil`, derives `collection?.id ?? itemType.id` (Collection override wins,
    /// LD-10). Lets the Templates pane target a specific container explicitly.
    var templateContainerID: String? = nil

    @Environment(ContextDisplayResolver.self) private var contextDisplay
    @Environment(TierConfigManager.self) private var tierConfigManager
    /// Used ONLY in edit mode to persist pin/unpin + reorder via the single
    /// template-persist path. Always injected wherever the renderer is hosted
    /// (live scene via `injectNexusEnvironment`; Templates popover injects the
    /// full env in T5.1), so this is quirk-#15-safe even though tests never
    /// instantiate the renderer in a host.
    @Environment(ItemTypeManager.self) private var itemTypeManager

    // MARK: - Derived template facts

    /// Effective archetype (defaulting to `.standard`) — the single read the
    /// layout + overflow branch derive from.
    private var archetype: LayoutArchetype { template.layout ?? .standard }

    /// The promoted set for this Item (Collection override → Type default), via
    /// the pure `TemplateResolver`. T3.3 formalizes the disjoint partition; here
    /// we only need the ordered promoted ids.
    private var promoted: [PromotedProperty] {
        TemplateResolver.promoted(type: itemType, collection: collection)
    }

    /// The user-defined schema (excludes the built-in tiers — those render in
    /// the relations region). Stored `properties` only, never `resolvedProperties`.
    private var userSchema: [PropertyDefinition] { itemType.properties }

    /// The three built-in tier relation definitions, merged with any sidecar
    /// overrides, in canonical order (Spaces / Topics / Projects labels).
    private var tierDefinitions: [PropertyDefinition] {
        itemType
            .resolvedProperties(tierConfig: tierConfigManager.config)
            .filter { ReservedPropertyID.isReserved($0.id) && $0.id != ReservedPropertyID.modifiedAt }
    }

    /// Promoted property ids (deduped, order-preserving) — the membership the
    /// overflow region subtracts from.
    private var promotedIDs: [String] { promoted.map(\.id) }

    /// The disjoint id partition for this Item: the full user-schema id list split
    /// into `main` (promoted, in promoted order) and `overflow` (the remainder, in
    /// schema order). The single source of truth both regions derive from — no id
    /// can land in both (Fix Log #10). See `partition(all:promoted:)`.
    private var idPartition: (main: [String], overflow: [String]) {
        Self.partition(all: userSchema.map(\.id), promoted: promotedIDs)
    }

    /// Non-promoted user properties — the overflow surface's content. Derived from
    /// the partition's `overflow` ids (schema order), so it's disjoint from
    /// `promotedSchema` by construction.
    private var overflowSchema: [PropertyDefinition] {
        let order = idPartition.overflow
        return order.compactMap { id in userSchema.first(where: { $0.id == id }) }
    }

    /// Promoted user properties, in promoted order, resolved to definitions paired
    /// with their promotion config. Disjoint from `overflowSchema` by construction:
    /// the shared `TemplateResolver.promotedEntries` reproduces the partition's
    /// `main` ordering (promoted order, real ids only), so the same join feeds both
    /// the live renderer here and the Templates pane (one source, review DRY #5).
    private var promotedSchema: [(promotion: PromotedProperty, definition: PropertyDefinition)] {
        TemplateResolver.promotedEntries(type: itemType, collection: collection)
    }

    /// Closure fed to every `PropertyCellDisplay` — wraps the shared env resolver
    /// (matches the detail-view call sites; keeps the cell pure of managers).
    private var relationResolver: (String) -> (icon: String, title: String)? {
        { contextDisplay.resolve($0) }
    }

    // MARK: - Promoted / overflow partition (pure)

    /// Splits the full ordered property-id list into the promoted set (main panel,
    /// in promoted order) and the overflow remainder, GUARANTEED disjoint — no id
    /// appears in both region (resolves the legacy double-render, Fix Log #10).
    /// Promoted ids not present in `all` are ignored; overflow preserves `all`'s
    /// order minus the promoted ids.
    ///
    /// Pure value code OUTSIDE any `@ViewBuilder` body, so `Array.contains` is safe
    /// here (quirk #12's GRDB String-overload ambiguity only bites inside views).
    static func partition(all: [String], promoted: [String]) -> (main: [String], overflow: [String]) {
        let promotedSet = Set(promoted)
        let main = promoted.filter { all.contains($0) }  // promoted order, real ids only
        let overflow = all.filter { !promotedSet.contains($0) }  // remainder, original order
        return (main, overflow)
    }

    // MARK: - Edit-mode reorder (pure, T3.5)

    /// Reorders the promoted list by ID (via `PropertyIDReorder.move`), PRESERVING
    /// each `PromotedProperty` entry (its per-property `display`). The edit-mode
    /// drag handler routes through this. Pure value code OUTSIDE any `@ViewBuilder`
    /// body, so it stays unit-testable without a SwiftUI host (quirk #12-safe).
    static func reorderPromoted(
        _ promoted: [PromotedProperty], moving: String, onto target: String
    ) -> [PromotedProperty] {
        let newIDOrder = PropertyIDReorder.move(promoted.map(\.id), moving: moving, onto: target)
        return newIDOrder.compactMap { id in promoted.first { $0.id == id } }
    }

    /// The container `template_config` edit writes persist to. Explicit
    /// `templateContainerID` wins; otherwise the Collection override (LD-10),
    /// falling back to the Type. Single source for every edit-mode write.
    private var writeTargetID: String {
        templateContainerID ?? (collection?.id ?? itemType.id)
    }

    // MARK: - Per-property display resolution (pure, T3.4)

    /// The display for a promoted property: its explicit per-property override
    /// (`PromotedProperty.display`) if set, else the archetype's default treatment
    /// for that property's type (LD-4). One source: per-property wins over archetype.
    static func resolvedDisplay(
        for promoted: PromotedProperty, propertyType: PropertyType, archetype: LayoutArchetype
    ) -> PropertyDisplay {
        if let explicit = promoted.display { return explicit }
        return archetypeDefaultDisplay(for: propertyType, archetype: archetype)
    }

    /// The archetype's default `PropertyDisplay` for a property type when no
    /// per-property override is set. Intentionally small: most types are `.inline`;
    /// image-forward archetypes give a `.file` property a `.thumbnail`/`.banner`
    /// treatment, and relations default to `.chips`. The point is the RESOLUTION
    /// logic (override wins) — not an exhaustive design matrix.
    static func archetypeDefaultDisplay(for type: PropertyType, archetype: LayoutArchetype) -> PropertyDisplay {
        switch type {
        case .relation:
            return .chips
        case .file:
            switch archetype {
            case .gallery: return .thumbnail
            case .bannerTwoColumn: return .banner
            default: return .inline
            }
        default:
            return .inline
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PUI.Spacing.xl) {
                if editing {
                    // Templates-pane mockup — the full archetype layout, where the
                    // template's properties are arranged (drag/pin). Reworked into
                    // the zone assigner in a later step.
                    header
                    coverSlot
                    mainRegion
                    overflowSurface
                    contextLinksRegion
                    metaRegion
                } else {
                    // LIVE window — a clean display-only stub: icon + title + body
                    // + footer, nothing else. The zone framework builds onto this
                    // bedrock; the half-built archetype regions above render ONLY in
                    // the mockup, never the live window.
                    header
                    stubBody
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                footer
            }
            .background(.bar)
        }
    }

    // MARK: - 1. Header (icon + title)

    /// Display-only header: the Item's icon (falling back to the Type's) + its
    /// title. Both modes render this identically — the live window is a display
    /// stub and the mockup arranges layout, not values, so neither edits here.
    private var header: some View {
        HStack(spacing: PUI.Spacing.md) {
            Image(systemName: item.icon ?? itemType.icon ?? "list.bullet.rectangle")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(item.title)
                .font(.title2.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Live-window body stub

    /// The live window's display-only body: the Item's description rendered with
    /// the read-only MarkdownPM editor (`isEditable: false` — no caret, no commit
    /// path). This is the stub bedrock the zone framework replaces; the editable
    /// editor + cap counter + save machinery were retired with the display stub.
    private var stubBody: some View {
        MarkdownPMEditor(
            text: .constant(item.description),
            configuration: MarkdownEditorConfig.pommora(verticalInset: 0),
            fontName: "SF Pro Text",
            fontSize: 15,
            documentId: item.id,
            isEditable: false
        )
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
    }

    // MARK: - 2. Cover slot

    /// Placeholder cover region when the template names a cover property. Real
    /// image loading is deferred (T3.4+); the slot reserves the banner geometry.
    @ViewBuilder
    private var coverSlot: some View {
        if let coverID = template.coverPropertyID,
            let coverDef = userSchema.first(where: { $0.id == coverID })
        {
            CoverSlotView(
                definition: coverDef,
                value: item.properties[coverID],
                relationResolver: relationResolver
            )
        }
    }

    // MARK: - 3. Main region (promoted + body)

    private var mainRegion: some View {
        AnyLayout(ItemWindowLayouts.layout(for: archetype)) {
            promotedRegion
            bodyRegion
        }
    }

    /// Promoted properties as icon + name + value rows, drawn from the partition's
    /// `main` ids (promoted order). Disjoint from `overflowSchema` by construction —
    /// both derive from the same `idPartition`, so no property renders twice.
    ///
    /// In edit mode each row becomes drag-reorderable and a pin/unpin "Add
    /// Property" affordance appears below; both writes go to `template_config`.
    /// In the live window NEITHER affordance renders — pure read-only.
    @ViewBuilder
    private var promotedRegion: some View {
        if promotedSchema.isEmpty && !editing {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: PUI.Spacing.md) {
                ForEach(promotedSchema, id: \.definition.id) { entry in
                    promotedRow(for: entry)
                }
                if editing {
                    addPropertyAffordance
                }
            }
        }
    }

    /// One promoted row. In edit mode it carries the inline native drag/drop
    /// (mirroring `PropertyVisibilityPane`): `.draggable(<id>)` +
    /// `.dropDestination(for: String.self)` routing through `reorderPromoted` and
    /// persisting via the single template-persist path.
    @ViewBuilder
    private func promotedRow(for entry: (promotion: PromotedProperty, definition: PropertyDefinition)) -> some View {
        let row = PropertyDisplayRow(
            definition: entry.definition,
            value: mockupValue(for: entry.definition),
            display: Self.resolvedDisplay(
                for: entry.promotion,
                propertyType: entry.definition.type,
                archetype: archetype
            ),
            relationResolver: relationResolver
        )
        if editing {
            row
                .draggable(entry.definition.id)
                .dropDestination(for: String.self) { droppedIDs, _ in
                    guard let droppedID = droppedIDs.first else { return false }
                    return reorderPromoted(droppedID: droppedID, ontoTargetID: entry.definition.id)
                }
        } else {
            row
        }
    }

    // MARK: - Edit-mode persistence (T3.5)

    /// Reorders the live promoted list and persists the new order to
    /// `template_config.promoted_properties` via the single writer. No-op when the
    /// order is unchanged. Returns whether the drop was accepted.
    private func reorderPromoted(droppedID: String, ontoTargetID: String) -> Bool {
        let current = promoted
        let newOrder = Self.reorderPromoted(current, moving: droppedID, onto: ontoTargetID)
        guard newOrder.map(\.id) != current.map(\.id) else { return false }
        let target = writeTargetID
        Task { try? await itemTypeManager.updateTemplateConfig(in: target) { $0.promotedProperties = newOrder } }
        return true
    }

    /// Pins (appends `PromotedProperty(id:, display: nil)`) or unpins (removes) a
    /// property, persisting the mutated promoted list to `template_config`. One
    /// path for both directions — pin/unpin is just a membership flip on the array.
    private func togglePin(_ propertyID: String, isPinned: Bool) {
        var newOrder = promoted
        if isPinned {
            newOrder.removeAll { $0.id == propertyID }
        } else if !newOrder.contains(where: { $0.id == propertyID }) {
            newOrder.append(PromotedProperty(id: propertyID, display: nil))
        }
        let target = writeTargetID
        Task { try? await itemTypeManager.updateTemplateConfig(in: target) { $0.promotedProperties = newOrder } }
    }

    /// The pin/unpin "Add Property" affordance — a `Menu` checklist of the Type's
    /// user properties; checking pins, unchecking unpins. Each toggle persists via
    /// `updateTemplateConfig`. Edit-mode only (gated by the caller).
    private var addPropertyAffordance: some View {
        let pinnedIDs = Set(promotedIDs)
        return Menu {
            ForEach(userSchema, id: \.id) { def in
                Toggle(
                    isOn: Binding(
                        get: { pinnedIDs.contains(def.id) },
                        set: { _ in togglePin(def.id, isPinned: pinnedIDs.contains(def.id)) }
                    )
                ) {
                    Label(def.name, systemImage: def.icon ?? def.type.pickerIcon)
                }
            }
        } label: {
            Label("Add Property", systemImage: "plus.circle")
                .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// The value to fill a promoted row in the mockup. In the live window (and
    /// whenever the Item carries a real value) it's the Item's value; in edit mode
    /// with no concrete value, a representative placeholder so the pane "looks like
    /// the item it governs" even for a template with no item.
    private func mockupValue(for definition: PropertyDefinition) -> PropertyValue? {
        if let real = item.properties[definition.id] { return real }
        guard editing else { return nil }
        return Self.placeholderValue(for: definition.type)
    }

    /// Representative placeholder value per property type for the edit-mode mockup.
    /// Pure value code (outside any `@ViewBuilder`) so the `switch` stays legible.
    /// Types whose placeholder would need a concrete reference (relations, files,
    /// the virtual last-edited timestamp) render empty rather than fabricate one.
    static func placeholderValue(for type: PropertyType) -> PropertyValue? {
        switch type {
        case .number: return .number(42)
        case .checkbox: return .checkbox(true)
        case .date: return .date(Date())
        case .datetime: return .datetime(Date())
        case .select: return .select("Option")
        case .multiSelect: return .multiSelect(["Option A", "Option B"])
        case .status: return .status("In Progress")
        case .url: return URL(string: "https://example.com").map(PropertyValue.url)
        case .relation, .file, .lastEditedTime: return nil
        }
    }

    /// The mockup body — a non-editable description placeholder. Renders only in
    /// the Templates-pane mockup (`mainRegion` is gated to edit mode); the live
    /// window uses `stubBody` instead. The mockup arranges layout, not values, so
    /// the editor and its commit path are absent here.
    private var bodyRegion: some View {
        Text(item.description.isEmpty ? "Description" : item.description)
            .font(.body)
            .foregroundStyle(item.description.isEmpty ? .tertiary : .secondary)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
    }

    // MARK: - 4. Overflow surface (non-promoted properties)

    /// The overflow region — exactly the partition's `overflow` properties (those
    /// NOT promoted into the main panel), so it never re-renders a promoted prop.
    /// Inspector archetypes get a side-pane column; everything else a disclosure
    /// dropdown (branch from T3.1, kept). Tiers render as their own rows ABOVE the
    /// user properties in inspector mode (handled in `inspectorOverflow`).
    @ViewBuilder
    private var overflowSurface: some View {
        if overflowSchema.isEmpty {
            EmptyView()
        } else if archetype.usesInspector {
            inspectorOverflow
        } else {
            dropdownOverflow
        }
    }

    private var inspectorOverflow: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.md) {
            Text("Properties")
                .font(.caption)
                .foregroundStyle(.secondary)
            // In inspector mode tiers render as their own rows above the user props.
            ForEach(tierDefinitions, id: \.id) { def in
                PropertyDisplayRow(
                    definition: def,
                    value: .relation(item.relationIDs(forPropertyID: def.id)),
                    display: .inline,
                    relationResolver: relationResolver
                )
            }
            ForEach(overflowSchema, id: \.id) { def in
                PropertyDisplayRow(
                    definition: def,
                    value: item.properties[def.id],
                    display: .inline,
                    relationResolver: relationResolver
                )
            }
        }
        .padding(PUI.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: PUI.Radius.small)
                .fill(Color(.quaternarySystemFill))
        )
    }

    private var dropdownOverflow: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: PUI.Spacing.md) {
                ForEach(overflowSchema, id: \.id) { def in
                    PropertyDisplayRow(
                        definition: def,
                        value: item.properties[def.id],
                        display: .inline,
                        relationResolver: relationResolver
                    )
                }
            }
            .padding(.top, PUI.Spacing.sm)
        } label: {
            Text("More properties")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 5. Relations region (tiers + relation properties)

    /// Tier relations always render here in the non-inspector layouts. In
    /// inspector mode tiers were promoted into the inspector overflow above, so
    /// this region only carries the user RELATION properties to avoid a double.
    private var contextLinksRegion: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.sm) {
            Text("Relations")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !archetype.usesInspector {
                ForEach(tierDefinitions, id: \.id) { def in
                    PropertyDisplayRow(
                        definition: def,
                        value: .relation(item.relationIDs(forPropertyID: def.id)),
                        display: .list,
                        relationResolver: relationResolver
                    )
                }
            }
        }
    }

    // MARK: - 6. Meta (modified date)

    private var metaRegion: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
            Text("Modified \(item.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 7. Footer (breadcrumb + options control)

    private var footer: some View {
        DetailFooterBar(crumbs: footerCrumbs) {
            Menu {
                // Template / view options land here (zone-framework rework).
                Text("Options")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var footerCrumbs: [FooterCrumb] {
        var crumbs = [FooterCrumb(title: itemType.title)]
        if let collection {
            crumbs.append(FooterCrumb(title: collection.title))
        }
        return crumbs
    }
}

// MARK: - PropertyDisplayRow (icon + name + value)

/// One promoted/overflow property row: the property's icon + name on the left,
/// the shared `PropertyCellDisplay` value on the right. Isolated as a plain
/// value-typed sub-view (quirk #12 — keeps GRDB String-overload pollution out of
/// the parent's `@ViewBuilder`). Pure read-side; T3.5 adds the edit affordance.
private struct PropertyDisplayRow: View {
    let definition: PropertyDefinition
    let value: PropertyValue?
    let display: PropertyDisplay
    let relationResolver: (String) -> (icon: String, title: String)?

    var body: some View {
        HStack(alignment: .top, spacing: PUI.Spacing.md) {
            HStack(spacing: PUI.Spacing.xs) {
                if let icon = definition.icon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(definition.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 140, alignment: .leading)

            PropertyCellDisplay(
                definition: definition,
                value: value,
                display: display,
                relationResolver: relationResolver
            )
            Spacer(minLength: 0)
        }
    }
}

// MARK: - CoverSlotView

/// Placeholder cover region. Real image loading is deferred (T3.4+); this frames
/// a banner-shaped slot and routes the cover value through `PropertyCellDisplay`'s
/// `.banner` treatment. Isolated as a plain value-typed sub-view (quirk #12).
private struct CoverSlotView: View {
    let definition: PropertyDefinition
    let value: PropertyValue?
    let relationResolver: (String) -> (icon: String, title: String)?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PUI.Radius.small)
                .fill(Color(.quaternarySystemFill))
            PropertyCellDisplay(
                definition: definition,
                value: value,
                display: .banner,
                relationResolver: relationResolver
            )
            .padding(PUI.Spacing.md)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
    }
}
