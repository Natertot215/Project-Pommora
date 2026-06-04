import SwiftUI

/// T3.1 — the single config-driven renderer that draws an Item Window from its
/// resolved template. This is the SKELETON; later tasks refine each region:
///   • T3.2 — body becomes the MarkdownPM editor + effective-cap counter
///   • T3.3 — formal promoted/overflow partition (disjoint, no double-render)
///   • T3.4 — per-property display (PropertyDisplay → PropertyCellDisplay.display)
///   • T3.5 — edit mode
///   • T3.6 — bespoke archetype region recipes (banner/two-column, gallery)
///
/// The renderer is read-only here and pure of CRUD/manager mutation paths — it
/// only READS the resolved `Item` + `ItemTemplateConfig` + schema, mirroring the
/// data-access patterns of the existing `ItemWindow` without depending on it.
///
/// Relation/tier display resolves through the shared `RelationDisplayResolver`
/// from the environment (the same instance every detail surface uses); the
/// resolver closure handed to `PropertyCellDisplay` is `{ relationDisplay.resolve($0) }`,
/// matching the detail-view call sites.
struct ItemWindowRenderer: View {
    let item: Item
    let template: ItemTemplateConfig
    let itemType: ItemType
    let collection: ItemCollection?

    @Environment(RelationDisplayResolver.self) private var relationDisplay
    @Environment(TierConfigManager.self) private var tierConfigManager

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

    /// Non-promoted user properties — the overflow surface's content.
    private var overflowSchema: [PropertyDefinition] {
        userSchema.filter { !promotedIDs.contains($0.id) }
    }

    /// Promoted user properties, in promoted order, resolved to definitions.
    private var promotedSchema: [(promotion: PromotedProperty, definition: PropertyDefinition)] {
        promoted.compactMap { promotion in
            guard let def = userSchema.first(where: { $0.id == promotion.id }) else { return nil }
            return (promotion, def)
        }
    }

    /// Closure fed to every `PropertyCellDisplay` — wraps the shared env resolver
    /// (matches the detail-view call sites; keeps the cell pure of managers).
    private var relationResolver: (String) -> (icon: String, title: String)? {
        { relationDisplay.resolve($0) }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PUI.Spacing.xl) {
                header
                coverSlot
                mainRegion
                overflowSurface
                relationsRegion
                metaRegion
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

    private var header: some View {
        HStack(spacing: PUI.Spacing.md) {
            Image(systemName: itemType.icon ?? item.icon ?? "list.bullet.rectangle")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(item.title)
                .font(.title2.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 2. Cover slot

    /// Placeholder cover region when the template names a cover property. Real
    /// image loading is deferred (T3.4+); the slot reserves the banner geometry.
    @ViewBuilder
    private var coverSlot: some View {
        if let coverID = template.coverPropertyID,
           let coverDef = userSchema.first(where: { $0.id == coverID }) {
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

    /// Promoted properties as icon + name + value rows. T3.3 formalizes the
    /// disjoint partition; here promoted-on-main / rest-below already guarantees
    /// no property renders twice (overflowSchema subtracts the promoted ids).
    @ViewBuilder
    private var promotedRegion: some View {
        if promotedSchema.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: PUI.Spacing.md) {
                ForEach(promotedSchema, id: \.definition.id) { entry in
                    PropertyDisplayRow(
                        definition: entry.definition,
                        value: item.properties[entry.definition.id],
                        display: entry.promotion.display ?? .inline,
                        relationResolver: relationResolver
                    )
                }
            }
        }
    }

    /// The description body. STUB: plain Text for now.
    // T3.2: replace with MarkdownPMEditor + effective-cap counter
    private var bodyRegion: some View {
        Text(item.description.isEmpty ? " " : item.description)
            .font(.body)
            .foregroundStyle(item.description.isEmpty ? .tertiary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    // MARK: - 4. Overflow surface (non-promoted properties)

    /// Inspector archetypes get a side-pane column; everything else a disclosure
    /// dropdown. A simple stub — T3.3 formalizes the partition + the inspector
    /// chrome. Tiers render as their own rows ABOVE the user properties in
    /// inspector mode (handled in `inspectorOverflow`).
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
    private var relationsRegion: some View {
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
                // T3.5: template / view options land here (edit mode, layout switch).
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
