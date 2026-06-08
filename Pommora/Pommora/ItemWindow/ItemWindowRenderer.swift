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
    /// `@Bindable` (not `let`) because the VM is owned by `ItemWindowHost`;
    /// this view observes + binds to it without taking ownership. The body binds
    /// through `$vm.draftBody` (D3) and the header binds `$vm.draftTitle` (D2).
    /// Mirrors `PageEditorView.viewModel`.
    @Bindable var vm: ItemWindowViewModel

    /// Panel identity — threaded to `ItemInspector` so its Delete can close THIS panel.
    let ref: ItemRef

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

    /// The Item Window's content for its floating panel: the main column
    /// (header row + property bar + body + breadcrumb footer) plus a native trailing
    /// `.inspector` panel (`ItemInspector` — the grouped Pages-style Tiers +
    /// Properties form) the system slides in/out and resizes. `vm.inspectorShown`
    /// (default `true`) drives the panel; the panel grows by the inspector's width
    /// when shown. The icon + inspector toggle live in the content `header` (a
    /// `.toolbar` does NOT render in an `NSHostingController`-hosted panel).
    var body: some View {
        // Panel layout: the main column IS the panel content; the inspector is a
        // real trailing `.inspector` panel (smooth system slide + resizable edge),
        // not a hand-laid second column. The panel's title bar is hidden and its
        // content extends under it (`.fullSizeContentView`), so the `header` reads
        // as the chrome with the standard close button at the top-left; the icon +
        // inspector toggle live in that header. The main column keeps its fixed
        // content width; the inspector adds its own width when shown.
        mainColumn
            .frame(width: PUI.ItemWindow.mainWidth)
            .inspector(isPresented: $vm.inspectorShown) {
                ItemInspector(
                    vm: vm,
                    ref: ref,
                    index: nexusManager.currentIndex,
                    resolver: contextResolver,
                    tierConfig: tierConfig.config
                )
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
            }
    }

    // MARK: - Main column (header + body + footer)

    /// Left column — an intrinsic-height content stack the card sizes itself to:
    /// header · top-separator · (6) · property bar (28) · (6) · body (310) · (6) ·
    /// bottom-separator · footer. No flexing middle and no trailing filler — the
    /// 6pt gaps are explicit, so there's no dead space below the body. No outer
    /// `ScrollView`; the body editor scrolls internally, so the chrome (header,
    /// footer) stays put. The bar renders only when chip properties are pinned,
    /// and owns its symmetric 6pt gaps (top-sep → bar == bar → body); the empty
    /// case substitutes one 6pt gap so the body never butts the header separator.
    private var mainColumn: some View {
        VStack(spacing: 0) {
            header
            // Top separator — inset to the body card's rail (matches the bar +
            // text-box horizontal extent) rather than spanning the full column.
            insetDivider
            // Pinned-property segmented bar (D4). Only rendered (with its symmetric
            // vertical gap) when chip properties are pinned — gated so the empty
            // case adds NO gap between the header divider and the body. When shown,
            // the renderer owns the symmetric gap (header-divider → bar == bar →
            // text-box), so the gap above the bar equals the gap below it.
            if hasPinnedFieldProperties {
                PropertyFieldBar(
                    itemType: vm.itemType,
                    collection: vm.collection,
                    values: vm.draftProperties,
                    onChange: { vm.handlePropertyChange($0, $1) }
                )
                // Symmetric 6pt gaps: top-sep → bar == bar → body (both `sm`).
                .padding(.top, PUI.Spacing.sm)
                .padding(.bottom, PUI.Spacing.sm)
            } else {
                // No bar → the single 6pt gap the body needs below the header
                // separator (so the body doesn't butt against the divider).
                Spacer().frame(height: PUI.Spacing.sm)
            }
            bodyZone
            // Fixed 6pt gap body → bottom separator (was a flexing `Spacer` that
            // left a dead gap under a fixed-height card; the card now sizes to
            // content, so this is an explicit 6pt symmetric gap, not a filler).
            Spacer().frame(height: PUI.Spacing.sm)
            // Bottom separator — same rail inset as the top one.
            insetDivider
            footer
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Whether the property-field bar has any pinned chip property to show — the
    /// same per-pool slice the bar itself computes (`PropertyFieldBar.segments`),
    /// so the gate never diverges from the bar's own self-collapse. Pure value code
    /// OUTSIDE the `@ViewBuilder` body (quirk #12 — `isEmpty`, no in-view `==`).
    private var hasPinnedFieldProperties: Bool {
        !PropertyFieldBar.segments(itemType: vm.itemType, collection: vm.collection).isEmpty
    }

    /// A horizontal separator inset to the body card's rail (the same horizontal
    /// extent the property bar + text-box align to), so the top + bottom
    /// separators read as bracketing the content column rather than the window.
    private var insetDivider: some View {
        Divider()
            .padding(.horizontal, PUI.Spacing.xl)
    }

    // MARK: - 1. Header row (icon + editable title + inspector toggle)

    /// The Item's header — the panel's chrome. The icon (leading) opens the picker
    /// and the inspector toggle (trailing) flank the editable title field; these
    /// moved here from a window `.toolbar`, which does NOT render in an
    /// `NSHostingController`-hosted panel. The panel hides its own title bar and the
    /// content extends under it (`.fullSizeContentView`), so the standard close
    /// button sits at the top-left and the leading inset clears it. The title
    /// commits on Enter (`onSubmit`) and focus-loss (`onChange`); the host's
    /// `.onDisappear` is the dismissal safety net (all idempotent —
    /// `handleTitleCommit` guards trimmed-equals-current).
    private var header: some View {
        HStack(spacing: PUI.Spacing.md) {
            // Icon — opens the picker. (The panel's standard close button sits to
            // its left; final flush/sizing polish lands in the design pass.)
            Button {
                showIconPicker = true
            } label: {
                Image(systemName: vm.draftIcon ?? vm.itemType.icon ?? "list.bullet.rectangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change icon")
            .iconPickerPopover(
                isPresented: $showIconPicker,
                symbol: Binding(get: { vm.draftIcon }, set: { vm.handleIconChange($0) })
            )

            TextField("Title", text: $vm.draftTitle)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .focused($titleFocused)
                .onSubmit { Task { await vm.handleTitleCommit() } }
                .onChange(of: titleFocused) { _, focused in
                    if !focused { Task { await vm.handleTitleCommit() } }
                }

            if let error = vm.inlineError {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                vm.inspectorShown.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Toggle inspector")
        }
        // Leading inset clears the panel's standard close button at the top-left.
        .padding(.leading, 56)
        .padding(.trailing, PUI.Spacing.md)
        .padding(.vertical, PUI.Spacing.sm)
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
    /// **Fixed-size input box (not a flexing region):** the card is clamped to a
    /// fixed `bodyHeight` (310pt) and spans the column's content rail (full width
    /// inset by the `xl` rail padding — the SAME extent the property bar +
    /// separators align to), so it does NOT grow to fill the column. The editor
    /// scrolls internally past the fixed height; the counter pins bottom-right
    /// inside the `quaternarySystemFill` rounded surface. The `mainColumn` sizes the
    /// card to this content (6pt gap to the bottom separator), so there's no dead
    /// gap below the body.
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
        // Fixed height — a defined input box, not a flexing fill. The editor
        // scrolls internally once content exceeds this.
        .frame(height: Self.bodyHeight)
        .background(
            Color(.quaternarySystemFill),
            in: RoundedRectangle(cornerRadius: PUI.Radius.medium, style: .continuous)
        )
        // Rail inset only — width follows the column's content rail (matches the
        // bar + separators), NOT an unbounded stretch beyond it.
        .padding(.horizontal, PUI.Spacing.xl)
    }

    /// Fixed height of the body input box. Sized so the editor reads as a defined
    /// multi-line description field rather than the column-dominating region it used
    /// to be — the card sizes to fit this exact content (no dead gap below it).
    private static let bodyHeight: CGFloat = 310

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
