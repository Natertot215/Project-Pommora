import SwiftUI

/// Live-editable inspector for the Item Window's trailing `.inspector` panel.
///
/// ONE unified flat-hairline menu on the native inspector glass — NOT a grouped
/// `Form`. Two groups with NO section headers and NO meta: the Context tiers
/// (Spaces / Topics / Projects) on top, then the schema properties, every row the
/// SAME shape — `[icon] [label] ··· [value editor]`, padded 6/12 with inset
/// `Divider()` hairlines between rows (mirrors the Pages `PropertyPanel`). A red
/// "Delete" text is pinned bottom-right over the scroll (replacing the old "Delete
/// Item" button). The value editors are reused as-is: `ContextValueEditor` for the
/// tier rows (it supplies its own "⊕ Add" empty state) and `PropertyEditorRow`
/// (`showsName: false`) for the property rows.
///
/// The shared row shell unifies GEOMETRY, not data: each call site passes its own
/// editor view (different binding types), so there's one row builder and two
/// editor kinds.
///
/// Quirk #15: reads NO `@Environment` managers directly — `index`, `resolver`, and
/// `tierConfig` are passed in by the renderer, so this view can't SIGTRAP on an
/// un-injected manager.
struct ItemInspector: View {
    @Bindable var vm: ItemWindowViewModel
    /// Panel identity — threaded from the renderer so Delete can close THIS panel
    /// via `AppGlobals.current?.itemWindowPanelManager.close(ref)`.
    let ref: ItemRef
    /// Live index for relation/tier candidate queries (`nexusManager.currentIndex`).
    let index: PommoraIndex?
    /// Resolves relation/tier IDs to icon + title chips.
    let resolver: ContextDisplayResolver
    /// Per-Nexus tier labels (drives the Tiers rows' titles via the canonical merge).
    let tierConfig: TierConfig

    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                contextsGroup
                // A small gap separates the two unlabeled groups (no headers).
                Spacer().frame(height: PUI.Spacing.sm)
                propertiesGroup
            }
        }
        // Red "Delete" pinned bottom-right, fixed over the scrolling content.
        .safeAreaInset(edge: .bottom, spacing: 0) { deleteFooter }
        .confirmationDialog(
            "Delete Item \"\(vm.item.title)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            // Delete FIRST, then close THIS panel (mirrors the old inspector flow).
            Button("Delete", role: .destructive) {
                Task { @MainActor in
                    await vm.confirmDelete()
                    AppGlobals.current?.itemWindowPanelManager.close(ref)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Shared row shell (one shape for both groups)

    /// One inspector row — `[icon] [label] ··· [value editor]`, padded 6/12 to match
    /// the Pages property panel. The `Spacer` right-aligns the editor; the caller
    /// supplies it (`ContextValueEditor` for tiers, `PropertyEditorRow(showsName:
    /// false)` — which omits its own trailing spacer — for properties).
    @ViewBuilder
    private func inspectorRow<Editor: View>(
        icon: String, label: String, @ViewBuilder editor: () -> Editor
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PUI.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: PUI.Spacing.md)
            editor()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }

    /// Inset hairline between rows (matches `PropertyPanel`).
    private var rowDivider: some View {
        Divider().padding(.horizontal, 12)
    }

    // MARK: - Contexts group (tiers — Spaces / Topics / Projects)

    @ViewBuilder
    private var contextsGroup: some View {
        ForEach(tierEntries) { entry in
            inspectorRow(icon: entry.icon, label: entry.label) {
                ContextValueEditor(
                    ids: tierBinding(entry.level),
                    scope: .contextTier(entry.level),
                    index: index,
                    resolver: resolver
                )
            }
            rowDivider
        }
    }

    /// One resolved tier: its level (1...3), the TierConfig label, and the merged
    /// icon — all from the canonical `resolvedProperties(tierConfig:)` merge (DRY).
    /// Pure value code OUTSIDE the `@ViewBuilder` (quirk #12 — the `case .contextTier`
    /// match + `compactMap`).
    private var tierEntries: [TierEntry] {
        vm.itemType.resolvedProperties(tierConfig: tierConfig)
            .compactMap { def in
                guard case .contextTier(let level) = def.relationTarget else { return nil }
                return TierEntry(level: level, label: def.name, icon: def.displayIcon)
            }
    }

    private struct TierEntry: Identifiable {
        let level: Int
        let label: String
        let icon: String
        var id: Int { level }
    }

    /// Two-way binding for tier `n`'s draft ID array, routing writes through the
    /// VM's `handleTierChange`. The fixed 1...3 set maps via a `switch` (HARD RULE).
    private func tierBinding(_ tier: Int) -> Binding<[String]> {
        switch tier {
        case 1: return Binding(get: { vm.draftTier1 }, set: { vm.handleTierChange(1, $0) })
        case 2: return Binding(get: { vm.draftTier2 }, set: { vm.handleTierChange(2, $0) })
        case 3: return Binding(get: { vm.draftTier3 }, set: { vm.handleTierChange(3, $0) })
        default: return .constant([])
        }
    }

    // MARK: - Properties group (built identically to the contexts group)

    @ViewBuilder
    private var propertiesGroup: some View {
        if vm.itemType.properties.isEmpty {
            Text("No properties defined in this Type's schema.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
        } else {
            let filled = filledPropertyIDs
            ForEach(propertyRowDefinitions(filled: filled)) { def in
                inspectorRow(icon: def.displayIcon, label: def.name) {
                    PropertyEditorRow(
                        definition: def,
                        value: propertyBinding(def.id),
                        index: index,
                        relationDisplay: resolver,
                        showsName: false
                    )
                }
                rowDivider
            }
            addPropertyMenu(filled: filled)
        }
    }

    /// IDs of draft properties that currently hold a non-empty value.
    /// Computed once per render pass and passed down to avoid duplicate traversals.
    private var filledPropertyIDs: Set<String> {
        Set(vm.draftProperties.filter { ItemWindowViewModel.isFilled($0.value) }.map(\.key))
    }

    /// Non-pinned, filled-or-surfaced schema properties (pinned ones live on the
    /// main-column chip bar, never here — exactly one place). Pure value code
    /// OUTSIDE the `@ViewBuilder` (quirk #12).
    private func propertyRowDefinitions(filled: Set<String>) -> [PropertyDefinition] {
        vm.itemType.properties.filter { def in
            !vm.pinnedIDs.contains(def.id)
                && (filled.contains(def.id) || vm.surfaced.contains(def.id))
        }
    }

    /// Schema properties still addable via the "Add property" menu. Pure value code
    /// OUTSIDE the `@ViewBuilder` (quirk #12).
    private func addableDefinitions(filled: Set<String>) -> [PropertyDefinition] {
        ItemWindowViewModel.addableProperties(
            schema: vm.itemType.properties, filled: filled, pinned: vm.pinnedIDs)
    }

    /// "Add property" affordance — a subtle menu surfacing each addable property's
    /// (empty) inspector row via `vm.addProperty`. Self-collapses (and adds no row
    /// padding) when nothing's addable.
    @ViewBuilder
    private func addPropertyMenu(filled: Set<String>) -> some View {
        let addable = addableDefinitions(filled: filled)
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
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
        }
    }

    private func propertyBinding(_ id: String) -> Binding<PropertyValue> {
        Binding(
            get: { vm.draftProperties[id] ?? .null },
            set: { vm.handlePropertyChange(id, $0) }
        )
    }

    // MARK: - Delete (red text, pinned bottom-right)

    private var deleteFooter: some View {
        HStack {
            Spacer()
            Button {
                showDeleteConfirm = true
            } label: {
                Text("Delete").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }
}
