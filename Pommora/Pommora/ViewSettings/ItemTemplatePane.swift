import SwiftUI

/// View Settings → Templates (ITEM scopes only).
///
/// Per-Type / per-Set template editor. Two stacked surfaces:
///   • the scope affordance — the Type-default ↔ Collection-override badge/reset
///     (`.itemCollection` only);
///   • the cover picker — a small menu writing `template_config.cover_property_id`.
///
/// (The archetype picker + WYSIWYG layout-preview + per-property display picker
/// were retired with the renderer's two-mode collapse; the interactive zones that
/// replace them are a later step.)
///
/// All template writes go through `ItemTypeManager.updateTemplateConfig` (the
/// single template-persist path).
///
/// The route is payload-free — the pane derives its container from its own
/// `scope` (mirrors PropertyVisibilityPane's `containerID()` / `side` pattern),
/// so the route never carries an entity. All reads re-query the live manager by
/// stable ID; reading the scope snapshot would render stale after a write.
///
/// Chrome routed through shared `ViewSettingsPane` + `PaneHeader` + `PUI` tokens.
struct ItemTemplatePane: View {
    let scope: ViewSettingsScope
    @Binding var path: [ViewSettingsRoute]

    @Environment(ItemTypeManager.self) private var itemTypeManager

    var body: some View {
        ViewSettingsPane {
            PaneHeader(path: $path)
        } content: {
            content
        }
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        // No ScrollView here — ViewSettingsPane owns the single scroll region.
        VStack(alignment: .leading, spacing: PUI.Spacing.xl) {
            scopeSection
            if let resolved = resolvedScope {
                coverSection(resolved)
            }
        }
    }

    // MARK: - Scope affordance (T5.4)
    //
    // The Type-default ↔ Collection-override relationship (LD-10). Collection
    // scope ONLY — a Type has nothing above it to inherit from, so the section
    // is empty for `.itemType`. When the Collection carries its OWN
    // `template_config`, it overrides the Type: surface an "Overrides Type
    // default" badge + a reset that clears the Collection's config to nil
    // (falling back to the Type). When it has none, it inherits the Type
    // default — a subtle hint, no reset.

    @ViewBuilder
    private var scopeSection: some View {
        if case .itemCollection = scope {
            if collectionOverridesType {
                ScopeOverrideRow(onReset: resetToTypeDefault)
            } else {
                ScopeInheritsRow()
            }
        }
    }

    /// True when the resolved scope is a Collection that carries its OWN
    /// `template_config` (a live read — re-queried from the manager so it
    /// reflects a reset/override immediately). A nil Collection config means it
    /// inherits the Type default and does NOT override.
    private var collectionOverridesType: Bool {
        guard case .itemCollection = scope, let cid = containerID() else { return false }
        for cols in itemTypeManager.itemCollectionsByType.values {
            if let c = cols.first(where: { $0.id == cid }) {
                return c.templateConfig != nil
            }
        }
        return false
    }

    // MARK: - Cover picker (T5.3)

    @ViewBuilder
    private func coverSection(_ resolved: ResolvedScope) -> some View {
        let eligible = Self.coverEligible(resolved.type.properties)
        VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
            sectionLabel("Cover image")
            if eligible.isEmpty {
                Text("No image file properties on this Type.")
                    .font(PUI.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, PUI.Row.paddingHorizontal)
            } else {
                CoverPickerRow(
                    eligible: eligible,
                    selectedID: currentCoverID,
                    onSelect: { setCover($0) }
                )
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(PUI.Typography.sectionHeader)
            .foregroundStyle(.secondary)
            .padding(.horizontal, PUI.Row.paddingHorizontal)
    }

    // MARK: - Pure helpers (unit-testable without a SwiftUI host)
    //
    // Pure value code OUTSIDE any `@ViewBuilder` body, so `Array`/`String`
    // collection methods stay free of the GRDB String-overload ambiguity (quirk
    // #12) and the helpers are testable without bootstrapping a view.

    /// The Type's properties eligible to be a template cover: `.file` properties
    /// whose `accept` admits an image MIME (`image/*` or a concrete `image/...`).
    /// Input order preserved.
    static func coverEligible(_ defs: [PropertyDefinition]) -> [PropertyDefinition] {
        defs.filter(isCoverEligible)
    }

    /// True when a single property may serve as a template cover: a `.file`
    /// property with at least one image entry in its `accept` whitelist. Uses
    /// `first(where:)` (quirk #12) instead of `contains` over the accept list.
    static func isCoverEligible(_ def: PropertyDefinition) -> Bool {
        guard def.type == .file, let accept = def.accept else { return false }
        return accept.first(where: Self.isImageAccept) != nil
    }

    /// Whether an `accept` pattern names an image MIME — the wildcard `image/*`
    /// or any concrete `image/<subtype>`.
    private static func isImageAccept(_ pattern: String) -> Bool {
        pattern == "image/*" || pattern.hasPrefix("image/")
    }

    // MARK: - Resolved scope (Type + optional Collection)

    /// The Type and its optional Collection. Bundled so the body resolves the
    /// scope once.
    struct ResolvedScope {
        let type: ItemType
        let collection: ItemCollection?
    }

    /// Resolves the scope to its Type + optional Collection. Re-queries the live
    /// manager by stable ID so it never renders stale after a write.
    private var resolvedScope: ResolvedScope? {
        switch scope {
        case .itemType(let t):
            guard let type = itemTypeManager.types.first(where: { $0.id == t.id }) else { return nil }
            return ResolvedScope(type: type, collection: nil)
        case .itemCollection(let c):
            guard let typeID = parentTypeID(),
                let type = itemTypeManager.types.first(where: { $0.id == typeID }),
                let collection = itemTypeManager.itemCollections(in: type).first(where: { $0.id == c.id })
            else { return nil }
            return ResolvedScope(type: type, collection: collection)
        default:
            return nil
        }
    }

    // MARK: - Current selection

    /// The scope's effective cover property id (live read).
    private var currentCoverID: String? {
        liveTemplateConfig?.coverPropertyID
    }

    /// The live `template_config` for the scope's own container (Type or
    /// Collection id), re-queried from the manager so reads never go stale.
    private var liveTemplateConfig: ItemTemplateConfig? {
        guard let cid = containerID() else { return nil }
        if let t = itemTypeManager.types.first(where: { $0.id == cid }) {
            return t.templateConfig
        }
        for cols in itemTypeManager.itemCollectionsByType.values {
            if let c = cols.first(where: { $0.id == cid }) {
                return c.templateConfig
            }
        }
        return nil
    }

    // MARK: - Commit

    /// Clears the Collection's OWN `template_config` to nil so the resolver
    /// falls back to the Type default (LD-10). Collection scope only — the
    /// affordance never renders for `.itemType`. After the clear, every pane
    /// read re-queries the manager by id, so the UI reflects the Type default.
    private func resetToTypeDefault() {
        guard let target = containerID() else { return }
        Task {
            try? await itemTypeManager.clearTemplateConfig(in: target)
        }
    }

    /// Sets the cover property id (nil clears it). Single template-persist path.
    private func setCover(_ propertyID: String?) {
        guard let target = containerID() else { return }
        Task {
            try? await itemTypeManager.updateTemplateConfig(in: target) { config in
                config.coverPropertyID = propertyID
            }
        }
    }

    // MARK: - Scope lookups
    //
    // Mirror PropertyVisibilityPane: extract the stable container ID once from
    // the scope, then re-query the live manager for every read. The scope-
    // resolved id IS the write target (Type id for `.itemType`, Collection id
    // for `.itemCollection`) so a Collection edit overrides only the Collection
    // (LD-10).

    private func containerID() -> String? {
        switch scope {
        case .itemType(let t): return t.id
        case .itemCollection(let c): return c.id
        default: return nil
        }
    }

    /// The parent ItemType id for a `.itemCollection` scope — read from the
    /// Collection's `typeID` (re-added after T5.2 removed it). Nil for other
    /// scopes.
    private func parentTypeID() -> String? {
        switch scope {
        case .itemCollection(let c): return c.typeID
        default: return nil
        }
    }
}

// MARK: - ScopeOverrideRow

/// Collection-scope override affordance (T5.4): an "Overrides Type default"
/// badge + a "Reset to Type default" button. Shown only when the Collection
/// carries its OWN `template_config`. The reset clears that config to nil so the
/// resolver falls back to the Type (LD-10).
private struct ScopeOverrideRow: View {
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: PUI.Row.interSpacing) {
            Text("Overrides Type default")
                .font(PUI.Typography.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, PUI.Spacing.sm)
                .padding(.vertical, PUI.Spacing.xs)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: PUI.Radius.small))
            Spacer()
            Button("Reset to Type default", action: onReset)
                .font(PUI.Typography.row)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)
    }
}

// MARK: - ScopeInheritsRow

/// Collection-scope inherit hint (T5.4): a subtle "Inherits Type default" label
/// shown when the Collection has no `template_config` of its own. No reset —
/// there's nothing to clear.
private struct ScopeInheritsRow: View {
    var body: some View {
        HStack {
            Text("Inherits Type default")
                .font(PUI.Typography.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)
    }
}

// MARK: - CoverPickerRow

/// The cover picker: a `Menu` of the Type's image-file properties plus a "None"
/// option. Isolated as a plain value-typed sub-view (quirk #12 — keeps GRDB
/// String-overload pollution out of the parent's `@ViewBuilder`).
private struct CoverPickerRow: View {
    let eligible: [PropertyDefinition]
    let selectedID: String?
    let onSelect: (String?) -> Void

    private var selectedName: String {
        guard let selectedID, let def = eligible.first(where: { $0.id == selectedID }) else {
            return "None"
        }
        return def.name
    }

    var body: some View {
        HStack(spacing: PUI.Row.interSpacing) {
            Text("Cover")
                .font(PUI.Typography.row)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("None") { onSelect(nil) }
                Divider()
                ForEach(eligible) { def in
                    Button {
                        onSelect(def.id)
                    } label: {
                        Label(def.name, systemImage: def.icon ?? "photo")
                    }
                }
            } label: {
                Text(selectedName)
                    .font(PUI.Typography.row)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)
    }
}

#if DEBUG
#Preview("ItemTemplatePane — ItemType scope") {
    ItemTemplatePane(
        scope: .itemType(
            ItemType(
                id: "01HIT", title: "Tasks", icon: "checklist",
                properties: [], views: [], modifiedAt: Date()
            )
        ),
        path: .constant([.itemTemplate])
    )
}
#endif
