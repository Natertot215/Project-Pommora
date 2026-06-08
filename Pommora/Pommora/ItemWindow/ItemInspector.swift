import SwiftUI

/// Live-editable inspector for the Item Window's trailing `.inspector` panel.
/// Mirrors the Pages inspector (`FrontmatterInspector`): a grouped `Form` with an
/// "Item" meta section, a "Tiers" section, and a "Properties" section — the native
/// macOS grouped material (rounded boxes + hairline-separated rows), NOT the old
/// hand-laid quaternary-fill column. Reuses the SAME row components the Pages
/// inspector uses — `ContextValueEditor` (tiers) and `PropertyEditorRow` (per-type
/// property editors) — driven by the live `ItemWindowViewModel`.
///
/// Quirk #15: reads NO `@Environment` managers directly — `index`, `resolver`, and
/// `tierConfig` are passed in by the renderer (which already holds them), so this
/// view can't SIGTRAP on an un-injected manager.
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
        Form {
            itemSection
            tiersSection
            propertiesSection
            deleteSection
        }
        .formStyle(.grouped)
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

    // MARK: - Item meta section (read-only — mirrors the Pages "Page" section)

    private var itemSection: some View {
        Section("Item") {
            LabeledContent("ID") {
                Text(vm.item.id)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            LabeledContent("Created", value: createdAtFormatted)
        }
    }

    private var createdAtFormatted: String {
        vm.item.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Tiers section

    private var tiersSection: some View {
        Section("Tiers") {
            ForEach(tierEntries) { entry in
                LabeledContent(entry.label) {
                    ContextValueEditor(
                        ids: tierBinding(entry.level),
                        scope: .contextTier(entry.level),
                        index: index,
                        resolver: resolver
                    )
                }
            }
        }
    }

    /// One resolved tier: its level (1...3) + the TierConfig label, from the
    /// canonical `resolvedProperties(tierConfig:)` merge (DRY — the same labels the
    /// property bar / page inspector resolve). Pure value code OUTSIDE the
    /// `@ViewBuilder` (quirk #12 — the `case .contextTier` match + `compactMap`).
    private var tierEntries: [TierEntry] {
        vm.itemType.resolvedProperties(tierConfig: tierConfig)
            .compactMap { def in
                guard case .contextTier(let level) = def.relationTarget else { return nil }
                return TierEntry(level: level, label: def.name)
            }
    }

    private struct TierEntry: Identifiable {
        let level: Int
        let label: String
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

    // MARK: - Properties section

    private var propertiesSection: some View {
        Section("Properties") {
            if vm.itemType.properties.isEmpty {
                Text("No properties defined in this Type's schema.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(propertyRowDefinitions) { def in
                    LabeledContent(def.name) {
                        PropertyEditorRow(
                            definition: def,
                            value: propertyBinding(def.id),
                            index: index,
                            relationDisplay: resolver,
                            showsName: false
                        )
                    }
                }
                addPropertyMenu
            }
        }
    }

    /// Non-pinned, filled-or-surfaced schema properties (pinned ones live on the
    /// main-column chip bar, never here — exactly one place). Pure value code
    /// OUTSIDE the `@ViewBuilder` (quirk #12 — `Set<String>.contains` + filter/map,
    /// never an in-view `==`).
    private var propertyRowDefinitions: [PropertyDefinition] {
        let filledIDs = Set(
            vm.draftProperties.filter { ItemWindowViewModel.isFilled($0.value) }.map(\.key))
        return vm.itemType.properties.filter { def in
            !vm.pinnedIDs.contains(def.id)
                && (filledIDs.contains(def.id) || vm.surfaced.contains(def.id))
        }
    }

    /// Schema properties still addable via the "Add property" menu. Pure value code
    /// OUTSIDE the `@ViewBuilder` (quirk #12).
    private var addableDefinitions: [PropertyDefinition] {
        let filledIDs = Set(
            vm.draftProperties.filter { ItemWindowViewModel.isFilled($0.value) }.map(\.key))
        return ItemWindowViewModel.addableProperties(
            schema: vm.itemType.properties, filled: filledIDs, pinned: vm.pinnedIDs)
    }

    /// "Add property" affordance — a subtle menu surfacing each addable property's
    /// (empty) inspector row via `vm.addProperty`. Self-collapses when nothing's addable.
    @ViewBuilder
    private var addPropertyMenu: some View {
        let addable = addableDefinitions
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
        }
    }

    private func propertyBinding(_ id: String) -> Binding<PropertyValue> {
        Binding(
            get: { vm.draftProperties[id] ?? .null },
            set: { vm.handlePropertyChange(id, $0) }
        )
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Section {
            Button("Delete Item", role: .destructive) {
                showDeleteConfirm = true
            }
        }
    }
}
