import MarkdownPM
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

    /// T3.5 — edit/mockup mode. When `true` the renderer becomes the WYSIWYG
    /// template-editing surface the Templates pane (T5.3) reuses: promoted rows
    /// gain drag-reorder + a pin/unpin "Add Property" affordance, both writing
    /// `template_config.promoted_properties`. When `false` (the LIVE window) the
    /// renderer is pure-render — NO edit affordances, and `promoted_properties`
    /// is NEVER mutated (only property VALUES are editable in the live window).
    var editing: Bool = false

    /// The container whose `template_config` edit-mode writes persist to. When
    /// `nil`, derives `collection?.id ?? itemType.id` (Collection override wins,
    /// LD-10). Lets the Templates pane target a specific container explicitly.
    var templateContainerID: String? = nil

    @Environment(RelationDisplayResolver.self) private var relationDisplay
    @Environment(TierConfigManager.self) private var tierConfigManager
    /// Used ONLY in edit mode to persist pin/unpin + reorder via the single
    /// template-persist path. Always injected wherever the renderer is hosted
    /// (live scene via `injectNexusEnvironment`; Templates popover injects the
    /// full env in T5.1), so this is quirk-#15-safe even though tests never
    /// instantiate the renderer in a host.
    @Environment(ItemTypeManager.self) private var itemTypeManager
    /// LIVE-window save target (T4.5). Same injected instance the old `.sheet`
    /// window used; satisfied by `injectNexusEnvironment` in the live scene
    /// (quirk #15-safe). Read only on the `editing == false` save path.
    @Environment(ItemContentManager.self) private var itemContentManager

    // MARK: - Description editor state (T3.2)

    /// Local draft of the Item's description (Markdown source). Seeded from
    /// `item.description` in `.task` (the renderer is memberwise-init-only, so
    /// there's no custom init to seed in). Edits are LOCAL @State only — the
    /// floating window isn't hosted live yet, so there's no commit path here.
    @State private var draftDescription: String = ""
    /// Per-document fold state for the MarkdownPM editor (UI-only).
    @State private var foldedHeadings: Set<String> = []

    // MARK: - Live-window save state (T4.5)
    //
    // These drive the LIVE window's save machinery and are ACTIVE only when
    // `editing == false`. In edit mode (template mockup) `hydrate()`/`save()`
    // never run and these stay at their seeds — that mode arranges layout, not
    // values. Ported from the old `.sheet` ItemWindow (deleted in T4.4).

    /// Editable title draft (LIVE window only). Seeded from `item.title`.
    @State private var draftTitle: String = ""
    /// Editable icon draft (SF Symbol name; empty == no icon). Seeded from `item.icon`.
    @State private var draftIcon: String = ""
    /// Item property values carried THROUGH the save unchanged. The live window
    /// keeps property rows read-only (no editor here), but the machinery persists
    /// this dict so a property-editing UI can land later without redoing the path.
    @State private var draftProperties: [String: PropertyValue] = [:]
    /// The ItemType schema captured at hydrate — the drift-detection baseline (EC4).
    @State private var originalItemType: ItemType?
    /// Set when drift is detected on save; drives the `SchemaConflictDialog` sheet.
    @State private var schemaConflict: SchemaConflictPayload?
    /// Surfaced save/validation failure (footer text).
    @State private var errorMessage: String?

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
    /// with their promotion config. Derived from the partition's `main` ids, so it's
    /// disjoint from `overflowSchema` by construction.
    private var promotedSchema: [(promotion: PromotedProperty, definition: PropertyDefinition)] {
        let promotionByID = Dictionary(promoted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return idPartition.main.compactMap { id in
            guard let promotion = promotionByID[id],
                  let def = userSchema.first(where: { $0.id == id })
            else { return nil }
            return (promotion, def)
        }
    }

    /// Closure fed to every `PropertyCellDisplay` — wraps the shared env resolver
    /// (matches the detail-view call sites; keeps the cell pure of managers).
    private var relationResolver: (String) -> (icon: String, title: String)? {
        { relationDisplay.resolve($0) }
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
    static func reorderPromoted(_ promoted: [PromotedProperty], moving: String, onto target: String) -> [PromotedProperty] {
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
    static func resolvedDisplay(for promoted: PromotedProperty, propertyType: PropertyType, archetype: LayoutArchetype) -> PropertyDisplay {
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
        // Seed every draft from the resolved Item. `.task` keys on `item.id` so
        // swapping the rendered Item reseeds. In edit mode (template mockup) only
        // the description seed matters; `hydrate()` is gated to the LIVE window.
        .task(id: item.id) {
            draftDescription = item.description
            if !editing { hydrate() }
        }
        // EC4 schema-drift dialog — LIVE window only (no payload is ever set in
        // edit mode because `save()` never runs there).
        .sheet(item: $schemaConflict) { payload in
            SchemaConflictDialog(
                isPresented: Binding(
                    get: { schemaConflict != nil },
                    set: { if !$0 { schemaConflict = nil } }
                ),
                removedPropertyNames: payload.removed,
                typeChangedPropertyNames: payload.typeChanged,
                onReload: {
                    reloadFromDisk()
                    schemaConflict = nil
                },
                onSaveValidSubset: { Task { await saveValidSubset() } },
                onCancel: { schemaConflict = nil }
            )
        }
    }

    // MARK: - Live-window save machinery (T4.5)
    //
    // Ported from the deleted `.sheet` ItemWindow. ACTIVE only when
    // `editing == false`. The renderer already holds `itemType` + `collection`
    // as `let` props (resolved by the scene root), so the old window's
    // `resolveItemType` / `resolveParentCollection` walks are unnecessary — the
    // container is known.

    /// Seeds the live-window drafts from `item` and captures `originalItemType`
    /// (the passed-in resolved type) as the drift baseline. Called from `.task`
    /// only when `editing == false`.
    private func hydrate() {
        draftTitle = item.title
        draftIcon = item.icon ?? ""
        draftProperties = item.properties
        originalItemType = itemType
    }

    /// Save with the EC4 schema-drift guard: reload the fresh on-disk schema,
    /// detect drift against the baseline, and either route to the conflict dialog
    /// (removed / type-changed props) or commit. Blank title is rejected.
    private func save() async {
        guard !draftTitle.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Title can't be empty."
            return
        }
        let baseline = originalItemType ?? itemType

        let metaURL = NexusPaths.itemTypeMetadataURL(
            in: itemContentManager.nexus.rootURL, typeFolderName: baseline.title
        )
        let freshType: ItemType
        do {
            freshType = try ItemType.load(from: metaURL)
        } catch {
            errorMessage = "Could not reload schema: \(error.localizedDescription)"
            return
        }

        let drift = SchemaConflictDetector.detectDrift(
            editingProperties: draftProperties,
            freshSchema: freshType.properties,
            originalSchema: baseline.properties
        )

        guard drift.removed.isEmpty && drift.typeChanged.isEmpty else {
            schemaConflict = SchemaConflictPayload(removed: drift.removed, typeChanged: drift.typeChanged)
            return
        }

        await commitSave(properties: draftProperties)
    }

    /// "Save valid subset" path from the conflict dialog: drop stale / type-
    /// mismatched values against the fresh schema, then commit the remainder.
    private func saveValidSubset() async {
        let baseline = originalItemType ?? itemType
        let metaURL = NexusPaths.itemTypeMetadataURL(
            in: itemContentManager.nexus.rootURL, typeFolderName: baseline.title
        )
        let freshType = (try? ItemType.load(from: metaURL)) ?? baseline
        let filtered = SchemaConflictDetector.filterToValidSubset(
            editingProperties: draftProperties,
            freshSchema: freshType.properties
        )
        schemaConflict = nil
        await commitSave(properties: filtered)
    }

    /// "Reload" path from the conflict dialog: re-read the Item + fresh schema
    /// from disk so the user re-edits against current truth. Uses `loadLenient`
    /// (the bulk-read surface) so an id-less adopted `.md` reloads instead of
    /// silently no-opping with a drifted draft.
    private func reloadFromDisk() {
        let baseline = originalItemType ?? itemType
        let folder: URL
        if let collection {
            folder = collection.folderURL
        } else {
            folder = itemContentManager.folderURL(for: baseline)
        }
        let itemURL = NexusPaths.itemFileURL(forTitle: item.title, in: folder)
        guard let reloaded = try? Item.loadLenient(from: itemURL) else { return }
        draftTitle = reloaded.title
        draftIcon = reloaded.icon ?? ""
        draftDescription = reloaded.description
        draftProperties = reloaded.properties

        let metaURL = NexusPaths.itemTypeMetadataURL(
            in: itemContentManager.nexus.rootURL, typeFolderName: baseline.title
        )
        if let freshType = try? ItemType.load(from: metaURL) {
            originalItemType = freshType
        }
        errorMessage = nil
    }

    /// Applies the drafts onto the Item and persists via the single
    /// `ItemContentManager.commitItemEdits` seam (Collection-scoped or Type-root
    /// chosen there). Maps save-path throws to a footer message.
    private func commitSave(properties: [String: PropertyValue]) async {
        let baseline = originalItemType ?? itemType
        do {
            try await itemContentManager.commitItemEdits(
                item,
                title: draftTitle,
                icon: draftIcon,
                description: draftDescription,
                properties: properties,
                type: baseline,
                collection: collection
            )
            errorMessage = nil
        } catch {
            errorMessage = surface(error)
        }
    }

    /// Maps a save-path throw to a user-facing message across BOTH domains the
    /// Item CRUD path raises: `ItemValidator.ValidationError` (schema/tier/body
    /// validation, via `friendly`) and any other `LocalizedError` (title
    /// collisions, rename atomicity, IO) via `localizedDescription`.
    private func surface(_ error: any Error) -> String {
        if let validation = error as? ItemValidator.ValidationError {
            return ItemValidator.friendly(validation)
        }
        return error.localizedDescription
    }

    // MARK: - 1. Header (icon + title)

    /// In the LIVE window (`editing == false`) the title + icon are editable
    /// (TextField bound to `$draftTitle`; SF Symbol field bound to `$draftIcon`,
    /// previewing the live glyph). In edit mode (template mockup) they stay
    /// non-editable placeholders — that mode arranges layout, not values.
    @ViewBuilder
    private var header: some View {
        if editing {
            HStack(spacing: PUI.Spacing.md) {
                Image(systemName: itemType.icon ?? item.icon ?? "list.bullet.rectangle")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Text(item.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: PUI.Spacing.md) {
                Image(systemName: draftIcon.isEmpty ? (itemType.icon ?? "list.bullet.rectangle") : draftIcon)
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
                    TextField("Title", text: $draftTitle)
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                        .onSubmit { Task { await save() } }
                    TextField("SF Symbol", text: $draftIcon)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(maxWidth: 200)
                        .onSubmit { Task { await save() } }
                }
                Spacer(minLength: 0)
            }
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
                Toggle(isOn: Binding(
                    get: { pinnedIDs.contains(def.id) },
                    set: { _ in togglePin(def.id, isPinned: pinnedIDs.contains(def.id)) }
                )) {
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

    /// The description body — the real MarkdownPM editor + an effective-cap
    /// counter. The cap reads `ItemValidator.effectiveCap(template: template)`
    /// off the RESOLVED template (Collection→Type, LD-10), so a Set overriding
    /// `descriptionCap` shows/colors against ITS cap, not the Type's — consistent
    /// with every other template field. Over-cap colorizes the counter only — it
    /// never blocks (LD-7). Edits are local @State; commit lands when live.
    @ViewBuilder
    private var bodyRegion: some View {
        if editing {
            // Template mockup — non-editable placeholder. The mockup arranges
            // layout, not values, so the editor (and its commit path) is absent.
            Text(item.description.isEmpty ? "Description" : item.description)
                .font(.body)
                .foregroundStyle(item.description.isEmpty ? .tertiary : .secondary)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        } else {
            DescriptionEditorRegion(
                text: $draftDescription,
                foldedHeadings: $foldedHeadings,
                documentId: item.id,
                cap: ItemValidator.effectiveCap(template: template)
            )
        }
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
            HStack(spacing: PUI.Spacing.md) {
                // LIVE window only: error surface + the Save affordance (the
                // commit trigger ported from the old window's footer button).
                if !editing {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    Button("Save") { Task { await save() } }
                        .keyboardShortcut("s", modifiers: .command)
                }
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

// MARK: - DescriptionEditorRegion (T3.2)

/// The Item Window's description body: the in-tree MarkdownPM editor plus a
/// non-blocking effective-cap counter. Isolated as a plain value-typed sub-view
/// (quirk #12 — keeps GRDB String-overload pollution out of the parent's
/// `@ViewBuilder`; `String.count` + the `>` comparison live here cleanly).
///
/// `documentId` is the Item id — per-Item undo history + editor state, NOT a
/// shared default (a bare `MarkdownPMEditor(text:)` init would default it to
/// `"default"`, sharing undo across every Item). The configuration reuses the
/// shared Pommora editor config (`MarkdownEditorConfig.pommora`) — vertical
/// inset 0 since the Item Window has no in-editor title overlay.
private struct DescriptionEditorRegion: View {
    @Binding var text: String
    @Binding var foldedHeadings: Set<String>
    let documentId: String
    let cap: Int

    private var count: Int { text.count }
    private var isOverCap: Bool {
        ItemValidator.descriptionCounterIsOverCap(count: count, cap: cap)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
            MarkdownPMEditor(
                text: $text,
                foldedHeadings: $foldedHeadings,
                configuration: MarkdownEditorConfig.pommora(verticalInset: 0),
                fontName: "SF Pro Text",
                fontSize: 15,
                documentId: documentId,
                onScrollOffsetChange: { _ in }
                // T4.4: wire commit/save when the floating window goes live.
            )
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)

            Text("\(count) / \(cap)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isOverCap ? Color.orange : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("\(count) of \(cap) characters")
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
