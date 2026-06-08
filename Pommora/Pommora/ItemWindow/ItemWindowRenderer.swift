import MarkdownPM
import SwiftUI

/// The single live Item-Window renderer. It draws the Item's icon + title
/// (`header`), an editable body with a character-cap counter (`bodyZone`), and a
/// breadcrumb footer — reading every field off the bound `ItemWindowViewModel`.
/// The body is editable (D3): edits route through `vm.handleBodyChange(_:)`. The
/// header title is still display-only; editable title / icon land in D2.
///
/// The reorder/partition helpers below (`partition`, `reorderPromoted`) are pure,
/// unit-tested, and retained for the zone rework even though no production caller
/// references them yet.
struct ItemWindowRenderer: View {
    /// `@Bindable` (not `let`) because the VM is owned by `ItemWindowSceneContent`;
    /// this view observes + binds to it without taking ownership. The body binds
    /// through `$vm.draftBody` (D3) and the header binds `$vm.draftTitle` (D2).
    /// Mirrors `PageEditorView.viewModel`.
    @Bindable var vm: ItemWindowViewModel

    /// Dismisses the hosting floating window after a delete or via the header's
    /// close affordance. Same idiom the enclosing `PreviewWindow` scene uses for
    /// its close button + Esc.
    @Environment(\.dismissWindow) private var dismissWindow

    /// Live index source for the tier fields' `ContextValueEditor` picker
    /// (`nexusManager.currentIndex`). All three of the env reads below are
    /// confirmed stored + injected by `injectNexusEnvironment` (quirk #15):
    /// `nexusManager`, `contextResolver`, `tierConfigManager` — so declaring
    /// them here can't SIGTRAP a `.task`-bearing render on first open.
    @Environment(NexusManager.self) private var nexusManager
    /// Resolves each tier relation ID to its target's icon + title (chips).
    @Environment(ContextDisplayResolver.self) private var contextResolver
    /// Per-Nexus tier labels (the field labels resolve through the canonical
    /// `ItemType.resolvedProperties(tierConfig:)` merge, which reads this).
    @Environment(TierConfigManager.self) private var tierConfig

    /// Drives the inspector column's destructive-delete confirmation dialog.
    @State private var showDeleteConfirm = false

    /// Focus for the inline title field. Drives focus-loss commit (D2): on
    /// `true → false` we flush `handleTitleCommit()`, matching the page editor's
    /// inline-title-commit idiom.
    @FocusState private var titleFocused: Bool

    /// Presents the header's icon picker popover (D2), anchored to the icon button.
    @State private var showIconPicker = false

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

    // MARK: - Body

    /// Two-column card scaffold: the main column (header + body + breadcrumb
    /// footer) on the left, the inspector column on the right, separated by a
    /// full-height vertical divider — the whole card framed to the fixed
    /// Item-Window dimensions. Each column owns its own bottom region: the
    /// breadcrumb footer pins to the bottom of the MAIN column; the Delete
    /// affordance pins to the bottom-right of the INSPECTOR column. There is NO
    /// full-width footer spanning both columns. The inspector is gated on
    /// `vm.inspectorShown` (defaults `true`, so the default render is both
    /// columns); D7 will add the conditional collapsed width when it's hidden.
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            mainColumn
            if vm.inspectorShown {
                Divider()
                inspectorColumn
            }
        }
        .frame(width: PUI.ItemWindow.totalWidth, height: PUI.ItemWindow.height)
    }

    // MARK: - Main column (header + body + footer)

    /// Left column — a fixed-top / flexing-middle / fixed-bottom stack: the icon +
    /// title header pinned up top, the editable body zone flexing to fill the
    /// space between, and the breadcrumb footer pinned to the bottom. No outer
    /// `ScrollView` — the body editor scrolls internally, so the column's chrome
    /// (header, footer) stays put. The property bar lands between the header
    /// `Divider()` and `bodyZone` in a later task (D-property-bar).
    private var mainColumn: some View {
        VStack(spacing: 0) {
            header
            Divider()
            // Pinned-property segmented bar (D4). Self-collapses (renders nothing,
            // no inset) when no chip properties are pinned; owns its own inset so
            // the empty case adds no gap between the header divider and the body.
            PropertyFieldBar(
                itemType: vm.itemType,
                collection: vm.collection,
                values: vm.draftProperties,
                onChange: { vm.handlePropertyChange($0, $1) }
            )
            bodyZone
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Inspector column

    /// Right column — fixed-width, full-height inspector. The three context-tier
    /// fields pin to the top (D5a, `tierFields`); property rows + the Add-Property
    /// affordance land in the gap below them in a later task (D5b). A `Spacer`
    /// holds that gap open and pushes the destructive Delete affordance to the
    /// column's bottom-right. The delete confirmation dialog is anchored here
    /// (relocated from the old full-width footer's options menu).
    private var inspectorColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // D5a: the three context-tier fields, pinned to the inspector's top.
            tierFields
            // D5b: property rows + the Add-Property control fill the gap between
            // the tier fields and the bottom Delete row.
            propertyRows
            addPropertyControl
            Spacer(minLength: 0)
            HStack {
                Spacer()
                deleteButton
            }
            .padding(PUI.Spacing.xl)
        }
        .frame(width: PUI.ItemWindow.inspectorWidth, alignment: .topLeading)
        .confirmationDialog(
            "Delete Item \"\(vm.item.title)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            // Delete FIRST, then dismiss: the now-deleted Item re-resolves to nil
            // in the scene's close flush, which safely no-ops (no resurrection).
            Button("Delete", role: .destructive) {
                Task {
                    await vm.confirmDelete()
                    dismissWindow()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Bare red "Delete" text (no button chrome) pinned to the inspector's
    /// bottom-right; taps arm the relocated confirmation dialog above.
    private var deleteButton: some View {
        Button("Delete", role: .destructive) { showDeleteConfirm = true }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
    }

    // MARK: - Tier fields (D5a)

    /// The three context-tier fields (Spaces / Topics / Projects) stacked at the
    /// inspector's top — each a filled field box carrying the tier's icon + label
    /// plus an inline `ContextValueEditor` for its relation chips. Drives off the
    /// canonical `ItemType.resolvedProperties(tierConfig:)` merge so the icons +
    /// labels are the SAME ones the property bar / page inspector resolve (DRY —
    /// no re-deriving "Spaces"/icon here). The `.contextTier(n)` entries arrive in
    /// tier order from the merge; each renders one `TierField`. Per-tier `==`/id
    /// work stays out of this `@ViewBuilder` — `tierProperties` is a plain helper
    /// and each row is its own value-typed sub-view (quirk #12).
    private var tierFields: some View {
        VStack(spacing: PUI.Spacing.md) {
            ForEach(tierProperties) { entry in
                TierField(
                    level: entry.level,
                    icon: entry.definition.icon ?? "circle",
                    label: entry.definition.name,
                    ids: tierBinding(entry.level),
                    index: nexusManager.currentIndex,
                    resolver: contextResolver
                )
            }
        }
        .padding(PUI.Spacing.xl)
    }

    /// One resolved tier row: its level (1...3) paired with the merged
    /// `PropertyDefinition` carrying that tier's icon + TierConfig label.
    private struct TierEntry: Identifiable {
        let level: Int
        let definition: PropertyDefinition
        var id: Int { level }
    }

    /// The merged tier relation properties (icon + TierConfig label per tier),
    /// reduced to `(level, definition)` pairs. The canonical merge emits the tiers
    /// last and in 1→3 order, and `compactMap` preserves that, so no re-sort here.
    /// Pure value code OUTSIDE the `@ViewBuilder` body, so the `case .contextTier`
    /// match + `compactMap` are quirk-12 safe. Reads the live `TierConfig` so a
    /// relabeled tier re-titles. The `.contextTier(n)` level is the single source
    /// of the row's tier number — never the array position.
    private var tierProperties: [TierEntry] {
        vm.itemType.resolvedProperties(tierConfig: tierConfig.config)
            .compactMap { def in
                guard case .contextTier(let level) = def.relationTarget else { return nil }
                return TierEntry(level: level, definition: def)
            }
    }

    /// Two-way binding for tier `n`'s draft ID array, routing writes through the
    /// VM's `handleTierChange` (which mutates the draft + fires the live save).
    /// Mirrors `FrontmatterInspector.tierBinding`; the fixed 1...3 set maps via a
    /// `switch`, any other level reads/writes nothing (HARD RULE: exhaustive flow).
    private func tierBinding(_ tier: Int) -> Binding<[String]> {
        switch tier {
        case 1: return Binding(get: { vm.draftTier1 }, set: { vm.handleTierChange(1, $0) })
        case 2: return Binding(get: { vm.draftTier2 }, set: { vm.handleTierChange(2, $0) })
        case 3: return Binding(get: { vm.draftTier3 }, set: { vm.handleTierChange(3, $0) })
        default: return .constant([])
        }
    }

    // MARK: - Property rows + Add-Property (D5b)

    /// The non-pinned, filled-or-surfaced schema properties to render as inspector
    /// rows, in schema order. Pinned properties are EXCLUDED — their chips live in
    /// the main column's `PropertyFieldBar`, never here (so a property is in exactly
    /// one place). Tiers aren't in `itemType.properties`, so they never reach here
    /// (they're handled by `tierFields` / D5a).
    ///
    /// Pure value code OUTSIDE any `@ViewBuilder` body (quirk #12). All membership
    /// tests are `Set<String>.contains` (the standard-library set lookup, unaffected
    /// by GRDB's `SQLSpecificExpressible` String overloads — that pollution only
    /// bites `Array.contains` / `==` on String inside a view body), and `filledIDs`
    /// is derived via `filter`/`map(\.key)`, never an in-view `==`.
    private var propertyRowDefinitions: [PropertyDefinition] {
        let pinnedIDs = Set(
            TemplateResolver.promotedForField(type: vm.itemType, collection: vm.collection)
                .map { $0.promotion.id })
        let filledIDs = Set(
            vm.draftProperties.filter { ItemWindowViewModel.isFilled($0.value) }.map(\.key))
        return vm.itemType.properties.filter { def in
            !pinnedIDs.contains(def.id) && (filledIDs.contains(def.id) || vm.surfaced.contains(def.id))
        }
    }

    /// One `InspectorPropertyRow` per filtered definition. Each row reads its current
    /// draft value and routes edits back through `vm.handlePropertyChange`. The
    /// `index` (drives the relation picker's candidate query) is `nexusManager`'s
    /// live index; the relation chips resolve via `contextResolver` — the same env
    /// reads the tier fields use. Self-collapses (no inset) when there are no rows.
    @ViewBuilder
    private var propertyRows: some View {
        let definitions = propertyRowDefinitions
        if !definitions.isEmpty {
            VStack(alignment: .leading, spacing: PUI.Spacing.md) {
                ForEach(definitions) { definition in
                    InspectorPropertyRow(
                        definition: definition,
                        value: vm.draftProperties[definition.id],
                        onChange: { vm.handlePropertyChange($0, $1) },
                        index: nexusManager.currentIndex,
                        resolver: contextResolver
                    )
                }
            }
            .padding(.horizontal, PUI.Spacing.xl)
            .padding(.top, PUI.Spacing.md)
        }
    }

    /// The schema properties still addable from the "Add property" menu — those not
    /// already filled, pinned, reserved, or the virtual last-edited-time. Pure value
    /// code OUTSIDE the `@ViewBuilder` (quirk #12); reuses `filledIDs`/`pinnedIDs`
    /// computed the same way as `propertyRowDefinitions`.
    private var addablePropertyDefinitions: [PropertyDefinition] {
        let pinnedIDs = Set(
            TemplateResolver.promotedForField(type: vm.itemType, collection: vm.collection)
                .map { $0.promotion.id })
        let filledIDs = Set(
            vm.draftProperties.filter { ItemWindowViewModel.isFilled($0.value) }.map(\.key))
        return ItemWindowViewModel.addableProperties(
            schema: vm.itemType.properties, filled: filledIDs, pinned: pinnedIDs)
    }

    /// "Add property" affordance below the property rows — a subtle `Menu` listing
    /// every addable schema property. Picking one surfaces its (empty) inspector row
    /// via `vm.addProperty(_:)`; no value is written until the user assigns one, so
    /// there's no seam call on add. Self-collapses when nothing is addable.
    @ViewBuilder
    private var addPropertyControl: some View {
        let addable = addablePropertyDefinitions
        if !addable.isEmpty {
            Menu {
                ForEach(addable) { def in
                    Button {
                        vm.addProperty(def.id)
                    } label: {
                        Label(def.name, systemImage: def.displayIcon)
                    }
                }
            } label: {
                Label("Add property", systemImage: "plus")
                    .font(PUI.Typography.row)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .padding(.horizontal, PUI.Spacing.xl)
            .padding(.top, PUI.Spacing.md)
        }
    }

    // MARK: - 1. Header (close · icon · title · inspector toggle)

    /// Interactive header bar (D2): `[✕ close] [icon] [Title field] … [inspector
    /// toggle]`. The Item Window is liquid glass, so the title field is fill-less
    /// (transparent — the glass shows through); no per-control glass effect.
    ///
    /// **Drag vs. clicks.** The whole bar moves the window, but `WindowDragGesture()`
    /// on the HStack itself would swallow the title field's click-to-focus and the
    /// buttons' taps. Instead the drag rides a dedicated `.background` drag layer
    /// (a hit-testable `Color.clear`) sitting *behind* the controls. SwiftUI
    /// hit-tests front-to-back, so a click on the title field / close / icon /
    /// toggle lands on that control first and never reaches the layer behind it;
    /// only a press on the empty header region falls through to the drag layer and
    /// moves the window. This mirrors `PreviewWindow`'s draggable header without
    /// stealing the interactive controls' input.
    private var header: some View {
        HStack(spacing: PUI.Spacing.md) {
            // 1. Close — copies PreviewWindow's plain `xmark` (no capsule chrome).
            Button {
                dismissWindow()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            // 2. Icon — Item icon (falling back to the Type's); tap opens the picker.
            Button {
                showIconPicker = true
            } label: {
                Image(systemName: vm.draftIcon ?? vm.itemType.icon ?? "list.bullet.rectangle")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change icon")
            .iconPickerPopover(
                isPresented: $showIconPicker,
                symbol: Binding(get: { vm.draftIcon }, set: { vm.handleIconChange($0) })
            )

            // 3. Title — inline-commit field, fill-less on the glass. Commits on
            // Enter (`onSubmit`) and focus-loss (`onChange`); the scene's
            // `.onDisappear` is the dismissal safety net. All idempotent
            // (`handleTitleCommit` guards trimmed-equals-current). `.fixedSize`
            // keeps the click/caret target on the text, not the whole bar.
            TextField("Title", text: $vm.draftTitle)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .focused($titleFocused)
                .onSubmit { Task { await vm.handleTitleCommit() } }
                .onChange(of: titleFocused) { _, focused in
                    if !focused { Task { await vm.handleTitleCommit() } }
                }
                .fixedSize(horizontal: true, vertical: false)

            // 4. Inline error — surfaces a rename failure (e.g. filename collision).
            if let error = vm.inlineError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // 6. Inspector toggle — same symbol Pommora uses in ContentView.
            Button {
                vm.inspectorShown.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Toggle inspector")
        }
        .padding(.horizontal, PUI.Spacing.md)
        .padding(.vertical, PUI.Spacing.sm)
        // Drag layer BEHIND the controls — only empty-region presses reach it.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
    }

    // MARK: - Body zone (editable description + cap counter)

    /// The Item's editable description: the MarkdownPM editor in editable mode
    /// (`isEditable: true`) above a character-cap counter. Every edit routes
    /// through `vm.handleBodyChange(_:)`, which updates `draftBody` and arms the
    /// VM's debounced save (mirroring `PageEditorView`, whose `text: $viewModel.body`
    /// binding lets `PageEditorViewModel.body`'s `didSet` schedule the save —
    /// `draftBody` has no `didSet`, so the binding's setter is the explicit route).
    /// Setting `draftBody` to the same value is a no-op, so there's no feedback loop.
    ///
    /// The counter reads the live draft length against the effective cap and turns
    /// red once `vm.isOverCap` (set when a flushed save exceeds the cap). The cap is
    /// a non-blocking WARN only — an over-cap body never blocks the editor (LD-7).
    ///
    /// The body is the dominant region: the editor frame flexes to fill the main
    /// column (no min/max height clamp), and the whole zone sits on a translucent
    /// `quaternarySystemFill` rounded surface with the counter pinned bottom-right.
    private var bodyZone: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
            MarkdownPMEditor(
                text: Binding(
                    get: { vm.draftBody },
                    set: { vm.handleBodyChange($0) }
                ),
                configuration: MarkdownEditorConfig.pommora(verticalInset: 0),
                fontName: "SF Pro Text",
                fontSize: 15,
                documentId: vm.item.id,
                isEditable: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Spacer()
                Text("\(vm.draftBody.count) / \(bodyCap)")
                    .font(.caption)
                    .foregroundStyle(vm.isOverCap ? .red : .secondary)
            }
        }
        .padding(PUI.Spacing.xl)
        .background(
            Color(.quaternarySystemFill),
            in: RoundedRectangle(cornerRadius: PUI.Radius.medium, style: .continuous)
        )
        .padding(PUI.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Effective description cap for the counter — the resolved template's override
    /// (Collection → Type) or the default. One source of truth: `ItemValidator`
    /// over the `TemplateResolver`-resolved template, matching `vm.flushBodyNow()`.
    private var bodyCap: Int {
        ItemValidator.effectiveCap(
            template: TemplateResolver.effective(type: vm.itemType, collection: vm.collection))
    }

    // MARK: - Footer (breadcrumb only)

    /// Breadcrumb path pinned to the bottom of the main column. No options menu,
    /// no Delete (that moved to the inspector column), and no opaque `.background`
    /// — the footer sits directly on the window glass; the `Divider()` above it in
    /// `mainColumn` is the only separator.
    private var footer: some View {
        DetailFooterBar(crumbs: footerCrumbs) { EmptyView() }
    }

    private var footerCrumbs: [FooterCrumb] {
        var crumbs = [FooterCrumb(title: vm.itemType.title)]
        if let collection = vm.collection {
            crumbs.append(FooterCrumb(title: collection.title))
        }
        return crumbs
    }
}

// MARK: - Tier field (D5a)

/// One full-width context-tier field box in the Item-Window inspector: the
/// tier's icon + label on the leading edge, with an inline `ContextValueEditor`
/// trailing that shows the tier's relation chips (or its own "Add" affordance
/// when empty). The label always names the tier, so an empty tier still reads as
/// "Spaces" / "Topics" / "Projects" rather than a bare "Add".
///
/// The box fill is the standard control-field background — `PUI.Fill.field`
/// (`.quinary`) at `PUI.Radius.field`, with a `.separator` hairline — the same
/// field-background language the Pages property inspector's context fields use
/// (and that `ContextChip` itself rides). Translucent, so the Item Window's
/// glass shows through while reading as a distinct menu/control field on top.
///
/// A pure value-typed sub-view (only `String` / `Binding<[String]>` / optional
/// index + resolver) so no GRDB-`String` overload ambiguity reaches a
/// `@ViewBuilder` here (quirk #12); the picker hosting is `ContextValueEditor`'s.
private struct TierField: View {
    /// Tier number (1...3) — drives the picker `scope`; the parent carries it
    /// explicitly (it's the `.contextTier(n)` level, never the array position).
    let level: Int
    let icon: String
    let label: String
    @Binding var ids: [String]
    let index: PommoraIndex?
    let resolver: ContextDisplayResolver

    var body: some View {
        HStack(spacing: PUI.Spacing.md) {
            Image(systemName: icon)
                .font(PUI.Icon.leading)
                .foregroundStyle(.secondary)
                .frame(width: PUI.Icon.leadingFrame)
            Text(label)
                .font(PUI.Typography.row)
                .foregroundStyle(.secondary)
            Spacer(minLength: PUI.Spacing.sm)
            ContextValueEditor(
                ids: $ids,
                scope: .contextTier(level),
                index: index,
                resolver: resolver
            )
        }
        .padding(.horizontal, PUI.Spacing.xl)
        .padding(.vertical, PUI.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PUI.Fill.field, in: RoundedRectangle(cornerRadius: PUI.Radius.field, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PUI.Radius.field, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}

// MARK: - Inspector property row (D5b)

/// One non-pinned property row in the Item-Window inspector. Lays the property's
/// identity out ONCE on the leading edge — `(icon) (name)` — then a `Spacer` and
/// the editable value/chip right-aligned: `(icon) (name) ────── (value)`. The row
/// itself is transparent (no fill); the value chips are the only filled element.
///
/// **No double-name.** This renders `Text(definition.name)` itself and is NEVER
/// wrapped in a `LabeledContent(name)` by its caller — so the name appears once
/// (the bug that `PropertyEditorRow` + `FrontmatterInspector`'s `LabeledContent`
/// wrapper produced is structurally avoided here).
///
/// A plain value-typed sub-view (`String` / `PropertyValue?` / closures / `Int` /
/// optionals) so no GRDB-`String` overload ambiguity reaches a `@ViewBuilder`
/// (quirk #12). The chip onPick toggle + id matching live in the value-typed
/// `InspectorChipField` below, mirroring `PropertyFieldBar`/`PropertyCellEditor`.
private struct InspectorPropertyRow: View {
    let definition: PropertyDefinition
    let value: PropertyValue?
    let onChange: (String, PropertyValue) -> Void
    /// Drives a relation field's candidate query (nil shows the picker's own empty state).
    let index: PommoraIndex?
    /// Resolves relation IDs to icon + title chips.
    let resolver: ContextDisplayResolver

    var body: some View {
        HStack(spacing: PUI.Spacing.md) {
            Image(systemName: definition.displayIcon)
                .font(PUI.Icon.leading)
                .foregroundStyle(.secondary)
                .frame(width: PUI.Icon.leadingFrame)
            Text(definition.name)
                .font(PUI.Typography.row)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: PUI.Spacing.sm)
            field
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Per-type field (the editable value/chip, trailing)

    @ViewBuilder
    private var field: some View {
        switch definition.type {
        case .select, .multiSelect, .status:
            InspectorChipField(definition: definition, value: value, onChange: onChange)
        case .checkbox:
            checkboxField
        case .number:
            numberField
        case .url:
            urlField
        case .date, .datetime:
            InspectorDateField(definition: definition, value: value, onChange: onChange)
        case .relation:
            relationField
        case .file, .lastEditedTime:
            // Read-only v1 fallback — file management + the virtual last-edited
            // timestamp aren't inline-editable here yet (flagged in the report).
            PropertyCellDisplay(definition: definition, value: value)
        }
    }

    // MARK: - Checkbox

    private var checkboxField: some View {
        Toggle(
            "",
            isOn: Binding(
                get: { if case .checkbox(let b) = value { return b } else { return false } },
                set: { onChange(definition.id, .checkbox($0)) }
            )
        )
        .labelsHidden()
    }

    // MARK: - Number (inline-commit on Enter + focus-loss)

    private var numberField: some View {
        InspectorTextField(
            placeholder: "",
            text: numberText,
            commit: { committed in
                let trimmed = committed.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    onChange(definition.id, .null)
                } else if let n = Double(trimmed) {
                    onChange(definition.id, .number(n))
                }
            }
        )
        .frame(maxWidth: 100)
    }

    private var numberText: String {
        if case .number(let n) = value { return n.formatted(.number.grouping(.never)) }
        return ""
    }

    // MARK: - URL (inline-commit on Enter + focus-loss)

    private var urlField: some View {
        InspectorTextField(
            placeholder: "https://…",
            text: urlText,
            commit: { committed in
                let trimmed = committed.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    onChange(definition.id, .null)
                } else if let url = URL(string: trimmed), url.scheme != nil {
                    onChange(definition.id, .url(url))
                }
            }
        )
        .frame(maxWidth: 160)
    }

    private var urlText: String {
        if case .url(let u) = value { return u.absoluteString }
        return ""
    }

    // MARK: - Relation

    @ViewBuilder
    private var relationField: some View {
        ContextValueEditor(
            ids: Binding(
                get: { if case .relation(let ids) = value { return ids } else { return [] } },
                set: { onChange(definition.id, .relation($0)) }
            ),
            scope: definition.relationTarget ?? .contextTier(1),
            index: index,
            resolver: resolver
        )
    }
}

// MARK: - Inspector inline text field (quirk #12-safe, inline-commit)

/// A right-aligned inline-commit `TextField` for the number / url rows. Commits on
/// Enter (`onSubmit`) AND focus-loss (`onChange(of:focused)`) — the Design.md
/// inline-commit rule (never Enter-only). `.fixedSize` keeps the caret/click target
/// on the text, not the row. A plain value-typed sub-view (only `String` + a
/// `commit` closure) so the GRDB-`String` overloads can't reach the parent's
/// `@ViewBuilder` (quirk #12); the local `@State` mirror is seeded from `text` and
/// kept in sync via `.onChange(of: text)`.
private struct InspectorTextField: View {
    let placeholder: String
    /// The committed value to display (the source of truth lives in the VM draft).
    let text: String
    let commit: (String) -> Void

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(PUI.Typography.row)
            .focused($focused)
            .fixedSize(horizontal: true, vertical: false)
            .onAppear { draft = text }
            .onChange(of: text) { _, new in
                // Re-sync the local mirror when the draft changes underneath us
                // (e.g. a clear from elsewhere), but never while the user is typing.
                if !focused { draft = new }
            }
            .onSubmit { commit(draft) }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit(draft) }
            }
    }
}

// MARK: - Inspector chip field (select / multiSelect / status — quirk #12-safe)

/// The trailing chip control for a select / multiSelect / status property row. Shows
/// the value as `PropertyChip` pill(s) when filled and a subtle "Set <name>"
/// placeholder when surfaced-but-empty; tapping opens the property's `ChipDropdown`
/// in a `.popover`. Mirrors `PropertyFieldBar`'s segment exactly, extended to cover
/// `.status` (options from `statusGroups`, value `.status(_)`).
///
/// A plain value-typed sub-view (quirk #12): all id matching uses `first(where:)` /
/// `firstIndex(of:)`, never `contains` / `==` on String in the body.
private struct InspectorChipField: View {
    let definition: PropertyDefinition
    let value: PropertyValue?
    let onChange: (String, PropertyValue) -> Void

    @State private var showDropdown = false
    /// Seeded `.onAppear` from the definition's options; a live `@State` binding so
    /// the multi-select dropdown can drag-reorder in-session (mirrors PropertyFieldBar).
    @State private var opts: [PropertyChipOption] = []

    var body: some View {
        Button {
            showDropdown = true
        } label: {
            label.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDropdown, arrowEdge: .bottom) {
            ChipDropdown(
                options: $opts,
                selectionMode: definition.type == .multiSelect ? .multi : .single,
                selectedIDs: Self.selectedIDs(from: value),
                onPick: { opt in apply(opt) },
                size: .compact
            )
            .presentationBackground(.clear)
        }
        .onAppear { opts = Self.allOptions(of: definition) }
    }

    @ViewBuilder
    private var label: some View {
        if ItemWindowViewModel.isFilled(value) {
            let chips = Self.filledChips(definition: definition, value: value)
            HStack(spacing: PUI.Spacing.xs) {
                ForEach(chips) { chip in
                    PropertyChip(label: chip.label, color: chip.color, size: .compact)
                }
            }
        } else {
            // Surfaced-but-empty placeholder — subtle, reads as "tap to set".
            Text("Set \(definition.name)")
                .font(PUI.Typography.row)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - onPick toggle (mirrors PropertyFieldBar / PropertyCellEditor)

    /// `.single` (select / status) → set the value, dismiss. `.multi` (multiSelect)
    /// → toggle the id; empty result clears (`.null`), else `.multiSelect(ids)`, and
    /// the dropdown stays open for further toggles.
    private func apply(_ opt: PropertyChipOption) {
        switch definition.type {
        case .multiSelect:
            var ids = Self.currentMultiIDs(from: value)
            if let i = ids.firstIndex(of: opt.id) {
                ids.remove(at: i)
            } else {
                ids.append(opt.id)
            }
            onChange(definition.id, ids.isEmpty ? .null : .multiSelect(ids))
        case .status:
            onChange(definition.id, .status(opt.id))
            showDropdown = false
        default:
            onChange(definition.id, .select(opt.id))
            showDropdown = false
        }
    }

    // MARK: - Plain value helpers (OUTSIDE the @ViewBuilder — quirk #12-safe)

    /// All options for this property as chip options. Select/multiSelect read
    /// `selectOptions`; status flattens `statusGroups` (each option inheriting its
    /// group color when it doesn't override).
    static func allOptions(of definition: PropertyDefinition) -> [PropertyChipOption] {
        switch definition.type {
        case .status:
            return (definition.statusGroups ?? []).flatMap { group in
                group.options.map { $0.asChipOption(groupColor: group.color) }
            }
        default:
            return (definition.selectOptions ?? []).map { $0.asChipOption() }
        }
    }

    /// The currently-selected ids as a `Set<String>` for the dropdown's `selectedIDs`.
    static func selectedIDs(from value: PropertyValue?) -> Set<String> {
        switch value {
        case .select(let id): return [id]
        case .status(let id): return [id]
        case .multiSelect(let ids): return Set(ids)
        default: return []
        }
    }

    /// The current multi-select ids as an ordered array (for the toggle).
    static func currentMultiIDs(from value: PropertyValue?) -> [String] {
        if case .multiSelect(let ids) = value { return ids }
        return []
    }

    /// The chip option(s) to render for a filled value — resolved against the
    /// definition's options so each pill shows the current label + color. Uses
    /// `first(where:)` (never `contains`); a stored id with no matching option is
    /// dropped (a deleted option can't crash the row).
    static func filledChips(
        definition: PropertyDefinition, value: PropertyValue?
    ) -> [PropertyChipOption] {
        let all = allOptions(of: definition)
        switch value {
        case .select(let id), .status(let id):
            return all.first(where: { $0.id == id }).map { [$0] } ?? []
        case .multiSelect(let ids):
            return ids.compactMap { id in all.first(where: { $0.id == id }) }
        default:
            return []
        }
    }
}

// MARK: - Inspector date field (date / datetime — replicates PropertyEditorRow's leaf)

/// The trailing date control for a date / datetime property row. A tappable field
/// pill showing the formatted value (or "Empty"), opening Pommora's `DateTimePicker`
/// in a chromeless popover. Replicates `PropertyEditorRow`'s date leaf verbatim
/// (DRY at the value-mapping layer via `PropertyValue.from(dateSelection:…)` and
/// `.dateSelection`), recast over the row's value-callback shape rather than a
/// two-way `Binding` — so the renderer's edits still route through
/// `vm.handlePropertyChange`. Time inclusion comes from the property's `timeFormat`.
///
/// A plain value-typed sub-view (quirk #12). Fully editable.
private struct InspectorDateField: View {
    let definition: PropertyDefinition
    let value: PropertyValue?
    let onChange: (String, PropertyValue) -> Void

    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            Text(displayString)
                .font(PUI.Typography.row)
                .foregroundStyle(hasValue ? .primary : .secondary)
                .padding(.horizontal, PUI.Spacing.md)
                .padding(.vertical, PUI.Spacing.xs)
                .fieldBackground()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            DateTimePicker(
                selection: selectionBinding,
                isTimeSet: isTimeSetBinding,
                mode: .single,
                timeFormat: definition.timeFormat ?? .none
            )
            .presentationBackground(.clear)
        }
    }

    private var hasValue: Bool { value?.dateSelection != nil }

    /// Formatted via the canonical `DateFormat` / `TimeFormat` renderers. Time is
    /// appended only when the stored value is `.datetime` (a `.date` means no time set).
    private var displayString: String {
        guard let date = value?.dateSelection?.anchorDate else { return "Empty" }
        let dateStr = (definition.dateFormat ?? .full).string(from: date)
        guard case .datetime = value,
            let time = (definition.timeFormat ?? .none).string(from: date)
        else { return dateStr }
        return "\(dateStr) \(time)"
    }

    private var selectionBinding: Binding<DateSelection?> {
        let timeFormat = definition.timeFormat ?? .none
        return Binding(
            get: { value?.dateSelection },
            set: { newSel in
                let hasTime: Bool
                if case .datetime = value { hasTime = true } else { hasTime = false }
                onChange(
                    definition.id,
                    .from(dateSelection: newSel, timeFormat: timeFormat, isTimeSet: hasTime))
            }
        )
    }

    private var isTimeSetBinding: Binding<Bool> {
        Binding(
            get: {
                if case .datetime = value { return true }
                return false
            },
            set: { newIsTimeSet in
                guard let date = value?.dateSelection?.anchorDate else { return }
                let tf = definition.timeFormat ?? .none
                guard tf.showsTime else { return }
                onChange(
                    definition.id,
                    .from(dateSelection: .single(date), timeFormat: tf, isTimeSet: newIsTimeSet))
            }
        )
    }
}
