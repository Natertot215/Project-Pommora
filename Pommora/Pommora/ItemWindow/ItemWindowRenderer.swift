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
    /// this view observes + binds to it without taking ownership. The body now
    /// binds through `$vm.draftBody` (D3); D2 will add the editable `$vm.draftTitle`.
    /// Mirrors `PageEditorView.viewModel`.
    @Bindable var vm: ItemWindowViewModel

    /// Dismisses the hosting floating window after a delete. Same idiom the
    /// enclosing `PreviewWindow` scene uses for its close affordance + Esc.
    @Environment(\.dismissWindow) private var dismissWindow

    /// Drives the footer options menu's destructive-delete confirmation.
    @State private var showDeleteConfirm = false

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

    /// Two-column card scaffold: the main column (header + body) on the left, the
    /// inspector column on the right, separated by a vertical divider — the whole
    /// card framed to the fixed Item-Window dimensions. The inspector is gated on
    /// `vm.inspectorShown` (defaults `true`, so the default render is both columns);
    /// D7 will add the conditional collapsed width when it's hidden. The footer
    /// spans the full card width as a bottom inset.
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            mainColumn
            if vm.inspectorShown {
                Divider()
                inspectorColumn
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                footer
            }
            .background(.bar)
        }
        .frame(width: PUI.ItemWindow.totalWidth, height: PUI.ItemWindow.height)
    }

    // MARK: - Main column (header + body)

    /// Left column — scrolling icon + title header above the editable body zone,
    /// flexing to fill the space left of the inspector.
    private var mainColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PUI.Spacing.xl) {
                header
                bodyZone
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Inspector column

    /// Right column — fixed-width inspector. Empty stub for now; D5 fills it with
    /// the inspector zone content.
    private var inspectorColumn: some View {
        Color.clear
            .frame(width: PUI.ItemWindow.inspectorWidth)
            .frame(maxHeight: .infinity)
    }

    // MARK: - 1. Header (icon + title)

    /// Display-only header: the Item's icon (falling back to the Type's) + its
    /// title. The live window is a display stub, so nothing edits here.
    private var header: some View {
        HStack(spacing: PUI.Spacing.md) {
            Image(systemName: vm.item.icon ?? vm.itemType.icon ?? "list.bullet.rectangle")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(vm.item.title)
                .font(.title2.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
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
            .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 200, alignment: .leading)

            HStack {
                Spacer()
                Text("\(vm.draftBody.count) / \(bodyCap)")
                    .font(.caption)
                    .foregroundStyle(vm.isOverCap ? .red : .secondary)
            }
        }
    }

    /// Effective description cap for the counter — the resolved template's override
    /// (Collection → Type) or the default. One source of truth: `ItemValidator`
    /// over the `TemplateResolver`-resolved template, matching `vm.flushBodyNow()`.
    private var bodyCap: Int {
        ItemValidator.effectiveCap(
            template: TemplateResolver.effective(type: vm.itemType, collection: vm.collection))
    }

    // MARK: - Footer (breadcrumb + options control)

    private var footer: some View {
        DetailFooterBar(crumbs: footerCrumbs) {
            Menu {
                // Delete is the only option for v1; template / view options
                // land here later (zone-framework rework).
                Button("Delete", role: .destructive) { showDeleteConfirm = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
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

    private var footerCrumbs: [FooterCrumb] {
        var crumbs = [FooterCrumb(title: vm.itemType.title)]
        if let collection = vm.collection {
            crumbs.append(FooterCrumb(title: collection.title))
        }
        return crumbs
    }
}
