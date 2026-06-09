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
        // as the chrome with a custom ✕ at the top-left; the icon + inspector toggle
        // live in that header. The hosted root is pinned to the fixed panel size; the
        // main column flexes within it and the inspector takes its share of the width.
        mainColumn
            .frame(maxWidth: .infinity)
            .inspector(isPresented: $vm.inspectorShown) {
                ItemInspector(
                    vm: vm,
                    ref: ref,
                    index: nexusManager.currentIndex,
                    resolver: contextResolver,
                    tierConfig: tierConfig.config
                )
                .inspectorColumnWidth(min: 240, ideal: 300, max: 420)
            }
            // Pin the hosted root to the fixed panel size (`.preferredContentSize`
            // is gone): the whole content is exactly width × height; the main column
            // flexes WITHIN that and the inspector takes its share of the width.
            .frame(width: PUI.ItemWindow.width, height: PUI.ItemWindow.height)
    }

    // MARK: - Main column (header + body + footer)

    /// Left column — fills the fixed panel height:
    /// header · top-separator · (6) · property bar (28) · (6) · body (fills) · (6) ·
    /// bottom-separator · footer. The body is the one flexing region; everything
    /// else is fixed, so the body takes the remaining height (no dead gap). No outer
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
            // Fixed 6pt gap between the (now-filling) body and the bottom separator.
            Spacer().frame(height: PUI.Spacing.sm)
            // Bottom separator — same rail inset as the top one.
            insetDivider
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    /// The Item's header — the panel's chrome. A custom ✕ (leading) is the only
    /// close affordance (the native traffic lights are hidden); the icon opens the
    /// picker and the inspector toggle (trailing) flank the editable title field.
    /// These moved here from a window `.toolbar`, which does NOT render in an
    /// `NSHostingController`-hosted panel. The panel hides its own title bar and the
    /// content extends under it (`.fullSizeContentView`), so the ✕ sits flush at the
    /// top-left behind a standard `md` gutter. The title is styled as a standard
    /// window title (single-line, truncating) so a long title never pushes the
    /// inspector toggle. The title commits on Enter (`onSubmit`) and focus-loss
    /// (`onChange`); the host's
    /// `.onDisappear` is the dismissal safety net (all idempotent —
    /// `handleTitleCommit` guards trimmed-equals-current).
    private var header: some View {
        HStack(spacing: PUI.Spacing.md) {
            // Custom ✕ — the native traffic lights are hidden; this is the only
            // close affordance (mirrors `PreviewWindow`'s header button styling).
            Button {
                AppGlobals.current?.itemWindowPanelManager.close(ref)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            // Icon — opens the picker. Sits flush after the ✕.
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
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        // Native buttons are hidden, so the custom ✕ sits flush — no traffic-light
        // clearance needed; the leading inset is just the standard `md` gutter.
        .padding(.leading, PUI.Spacing.md)
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
    /// **Fills the fixed panel frame:** the body is the column's flexing region —
    /// header, bar, separators, and footer are fixed, so the body takes the
    /// remaining height. It spans the content rail (full width inset by the `xl`
    /// rail padding — the SAME extent the property bar + separators align to). The
    /// editor scrolls internally past the visible height; the counter pins
    /// bottom-right inside the `quaternarySystemFill` rounded surface.
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
        // Fills the remaining height — the body is the flexing region; the editor
        // scrolls internally once content exceeds the visible box.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color(.quaternarySystemFill),
            in: RoundedRectangle(cornerRadius: PUI.Radius.medium, style: .continuous)
        )
        // Rail inset only — width follows the column's content rail (matches the
        // bar + separators), NOT an unbounded stretch beyond it.
        .padding(.horizontal, PUI.Spacing.xl)
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
