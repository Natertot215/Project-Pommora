import SwiftUI

// MARK: - PagePreviewInspector

/// The PagePreview card's inspector pane (Figma V8). A leaner, ungrouped take on
/// the main editor's `FrontmatterInspector` — no "Page" meta section, no section
/// headers, no Add/Delete affordances. Two zones only, matching the frame:
///
///   1. A grouped **context card** at the top — exactly THREE tier rows
///      (Spaces / Topics / Projects), each `icon + tier name + value editor`,
///      inside one rounded container with hairline dividers between rows and a
///      subtle quaternary fill (the card's glass shell is the one glass surface;
///      glass can't sample glass, so the group uses a material/quaternary fill,
///      never a nested `.glassEffect`).
///   2. A gap, then a **plain property list** — one row per `vault.properties`
///      entry (`icon + name + value editor`), no container, no dividers, no fill.
///
/// Reuses the existing machinery verbatim:
/// - Driven by the same `FrontmatterInspectorViewModel` the main inspector uses
///   (debounced 300ms save via `onSave`), constructed on first appear.
/// - Tier rows reuse `ContextValueEditor` (`scope: .contextTier(N)`), bound to
///   the VM's `draftTierN` through `handleTierChange`.
/// - Property rows reuse `PropertyEditorRow(showsName: false)` — this view owns
///   the row layout (icon + name + flush-right editor), so the editor's own name
///   label and trailing spacer are suppressed.
struct PagePreviewInspector: View {
    let page: PageMeta
    let vault: PageType
    let index: PommoraIndex?
    let relationDisplay: ContextDisplayResolver?
    let onSave: ((PageFrontmatter) -> Void)?

    @Environment(TierConfigManager.self) private var tierConfigManager

    @State private var vm: FrontmatterInspectorViewModel?

    init(
        page: PageMeta,
        vault: PageType,
        index: PommoraIndex? = nil,
        relationDisplay: ContextDisplayResolver? = nil,
        onSave: ((PageFrontmatter) -> Void)? = nil
    ) {
        self.page = page
        self.vault = vault
        self.index = index
        self.relationDisplay = relationDisplay
        self.onSave = onSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PUI.Spacing.xxl) {
                contextGroup
                propertyList
            }
            .padding(.horizontal, PUI.Spacing.md)
            .padding(.vertical, Self.topInset)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { initVM() }
    }

    /// Top inset chosen so the middle context row's baseline lands near the
    /// card's header separator (per the V8 spec).
    private static let topInset: CGFloat = PUI.Spacing.lg

    // MARK: - Context group (3 tier rows, grouped + divided)

    /// The three tier definitions, merged from `BuiltInContextLinkProperties`
    /// so the leading icon + display name track the nexus's TierConfig and any
    /// per-Vault sidecar override (single source of truth for tier display).
    private var tierDefinitions: [PropertyDefinition] {
        BuiltInContextLinkProperties
            .merge(existing: [], tierConfig: tierConfigManager.config, sourceTypeID: vault.id)
            .filter { ReservedPropertyID.isReserved($0.id) }
    }

    private var contextGroup: some View {
        VStack(spacing: 0) {
            let defs = tierDefinitions
            ForEach(Array(defs.enumerated()), id: \.element.id) { offset, def in
                tierRow(def)
                if offset < defs.count - 1 {
                    // Full-bleed hairline between rows (edge-to-edge in the group),
                    // per the V8 frame.
                    Divider()
                }
            }
        }
        .background(
            .quaternary,
            in: RoundedRectangle(cornerRadius: PUI.Radius.large, style: .continuous)
        )
    }

    @ViewBuilder
    private func tierRow(_ def: PropertyDefinition) -> some View {
        if let model = vm, let tier = ReservedPropertyID.tierNumber(forID: def.id) {
            inspectorRow(icon: def.displayIcon, name: def.name) {
                ContextValueEditor(
                    ids: tierBinding(model, tier),
                    scope: .contextTier(tier),
                    index: index,
                    resolver: relationDisplay
                )
            }
        } else {
            inspectorRow(icon: def.displayIcon, name: def.name) {
                Text("—").foregroundStyle(.tertiary).font(PUI.Typography.row)
            }
        }
    }

    /// `tier` is always one of {1,2,3} (sourced from
    /// `ReservedPropertyID.tierNumber(forID:)`). The getter routes off that level;
    /// the setter funnels every write back through the VM's single
    /// `handleTierChange` entry point, so all three tiers share one save path.
    private func tierBinding(_ model: FrontmatterInspectorViewModel, _ tier: Int) -> Binding<[String]> {
        Binding(
            get: {
                switch tier {
                case 1: return model.draftTier1
                case 2: return model.draftTier2
                case 3: return model.draftTier3
                case _: return []
                }
            },
            set: { model.handleTierChange(tier, $0) }
        )
    }

    // MARK: - Property list (plain, ungrouped)

    @ViewBuilder
    private var propertyList: some View {
        if vault.properties.isEmpty {
            Text("No properties defined.")
                .font(PUI.Typography.row)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, Self.rowInset)
        } else if let model = vm {
            VStack(spacing: 0) {
                ForEach(vault.properties) { prop in
                    inspectorRow(icon: prop.displayIcon, name: prop.name) {
                        PropertyEditorRow(
                            definition: prop,
                            value: Binding(
                                get: { model.draftProperties[prop.id] ?? .null },
                                set: { newVal in model.handlePropertyChange(prop.id, newVal) }
                            ),
                            index: index,
                            relationDisplay: relationDisplay,
                            showsName: false
                        )
                    }
                }
            }
        }
    }

    // MARK: - Shared row chrome (icon + name + trailing editor)

    /// Leading inset of a row's content — the icon's left edge. Shared by the
    /// grouped context rows and the plain property rows so both align.
    private static let rowInset: CGFloat = PUI.Spacing.xl

    private func inspectorRow(
        icon: String, name: String, @ViewBuilder editor: () -> some View
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PUI.Spacing.md) {
            Image(systemName: icon)
                .font(PUI.Icon.leading)
                .foregroundStyle(.secondary)
                .frame(width: PUI.Icon.leadingFrame, alignment: .center)
            Text(name)
                .font(PUI.Typography.row)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: PUI.Spacing.md)
            editor()
        }
        .padding(.horizontal, Self.rowInset)
        .padding(.vertical, PUI.Spacing.md)
    }

    // MARK: - VM lifecycle

    private func initVM() {
        if vm == nil {
            vm = FrontmatterInspectorViewModel(page: page, vault: vault, onSave: onSave)
        }
    }
}
