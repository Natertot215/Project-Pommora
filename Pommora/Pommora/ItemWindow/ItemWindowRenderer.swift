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
            // D5b: property rows + Add-Property land in the gap the Spacer holds
            // open between the tier fields and the bottom Delete row.
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
