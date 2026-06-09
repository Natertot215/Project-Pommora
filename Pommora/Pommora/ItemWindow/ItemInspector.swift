import SwiftUI

/// Live-editable inspector for the Item Window's trailing `.inspector` panel.
///
/// A native grouped `Form` (`.formStyle(.grouped)`) — the SAME mechanism the Pages
/// inspector (`FrontmatterInspector`) uses, so the Item inspector inherits macOS's
/// rounded "menu-background" cards + hairline row separators for free and reads
/// identically to the Pages side. Two UNLABELED sections (no headers, no meta): the
/// Context tiers (Spaces / Topics / Projects) on top, then the schema properties.
/// Each row is `[icon] [label] ··· [value editor]` via `LabeledContent` with a
/// leading `Label` (the Figma's per-row icon). A red "Delete" text is pinned
/// bottom-right over the form (inactive grey at rest, red on hover, breadcrumb
/// `.subheadline` scale). The value editors are reused as-is: `ContextValueEditor`
/// for the tier rows and `PropertyEditorRow(showsName: false)` for the property rows
/// (the `LabeledContent` label already carries the name + icon).
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
    /// Hover state for the Delete affordance — grey (inactive) at rest, red on hover.
    @State private var deleteHover = false

    var body: some View {
        Form {
            // Contexts group — unlabeled card (the tier rows are self-evidently contexts).
            Section {
                ForEach(tierEntries) { entry in
                    LabeledContent {
                        ContextValueEditor(
                            ids: tierBinding(entry.level),
                            scope: .contextTier(entry.level),
                            index: index,
                            resolver: resolver
                        )
                    } label: {
                        Label(entry.label, systemImage: entry.icon)
                    }
                }
            }

            // Properties group — unlabeled card.
            Section {
                propertyRows
            }
        }
        .formStyle(.grouped)
        // Red "Delete" pinned bottom-right, fixed over the scrolling form.
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

    // MARK: - Contexts group (tiers — Spaces / Topics / Projects)

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

    // MARK: - Properties group

    @ViewBuilder
    private var propertyRows: some View {
        if vm.itemType.properties.isEmpty {
            Text("No properties defined in this Type's schema.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            let filled = filledPropertyIDs
            ForEach(propertyRowDefinitions(filled: filled)) { def in
                LabeledContent {
                    PropertyEditorRow(
                        definition: def,
                        value: propertyBinding(def.id),
                        index: index,
                        relationDisplay: resolver,
                        showsName: false
                    )
                } label: {
                    Label(def.name, systemImage: def.displayIcon)
                }
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

    /// "Add property" affordance — a subtle footnote/secondary menu surfacing each
    /// addable property's (empty) row via `vm.addProperty`. Self-collapses when
    /// nothing's addable.
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
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func propertyBinding(_ id: String) -> Binding<PropertyValue> {
        Binding(
            get: { vm.draftProperties[id] ?? .null },
            set: { vm.handlePropertyChange(id, $0) }
        )
    }

    // MARK: - Delete (inactive → red on hover, breadcrumb scale, pinned bottom-right)

    private var deleteFooter: some View {
        HStack {
            Spacer()
            Button {
                showDeleteConfirm = true
            } label: {
                // `.subheadline` matches the main-window breadcrumb scale; grey at
                // rest (inactive), red on hover (active) — so a destructive action
                // never reads as prominent until intended.
                Text("Delete")
                    .font(.subheadline)
                    .foregroundStyle(deleteHover ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .onHover { deleteHover = $0 }
            .animation(.smooth(duration: 0.15), value: deleteHover)
        }
        .padding(.horizontal, PUI.Spacing.xl)
        .padding(.vertical, PUI.Spacing.sm)
    }
}
