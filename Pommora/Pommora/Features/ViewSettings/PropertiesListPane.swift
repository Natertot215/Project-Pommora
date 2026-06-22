import SwiftUI

/// View Settings → Edit Properties → schema-only list of the active Type's
/// USER-DEFINED properties. Reserved/built-in columns (tier relations,
/// Modified, and the other reserved IDs) are non-editable and so are excluded
/// from display entirely — their per-view visibility is controlled by the
/// Layout pane's eye-list, not here. User-defined properties push to
/// `EditPropertyPane` via the chevron.
///
/// Footer "+ New property" button pushes `PropertyTypePickerPane` so the
/// user picks a type before naming + configuring.
///
/// Schema ownership: properties live on the PageType. For Collection
/// scopes the pane resolves the parent Type via the manager (PageTypeManager
/// looked up from @Environment).
///
/// Chrome routed through shared `PaneHeader` + `PUI` tokens for uniformity
/// with every other View Settings sub-pane.
struct PropertiesListPane: View {
    let scope: ViewSettingsScope
    @Binding var path: [ViewSettingsRoute]

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(TierConfigManager.self) private var tierConfigManager

    @State private var searchQuery: String = ""

    var body: some View {
        ViewSettingsPane {
            PaneHeader(path: $path)
        } content: {
            propertyList
        } footer: {
            // Pinned: the divider + global "New property" action.
            VStack(spacing: 0) {
                PaneDivider()
                footer
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - List

    @ViewBuilder
    private var propertyList: some View {
        let props = filteredProperties()
        if props.isEmpty {
            emptyState
        } else {
            // No ScrollView here — ViewSettingsPane owns the single scroll
            // region and measures this content's natural height.
            VStack(spacing: 0) {
                ForEach(props, id: \.id) { def in
                    PropertyRow(definition: def) {
                        // Reserved properties are non-interactive; only
                        // user-defined push to EditPropertyPane.
                        guard !ReservedPropertyID.isReserved(def.id) else { return }
                        path.append(.editProperty(propertyID: def.id))
                    }
                }
            }
        }
    }

    private func filteredProperties() -> [PropertyDefinition] {
        let all = resolvedProperties()
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Resolves the parent Type's properties for any storage scope by
    /// looking up the live Type from the manager via its stable ID.
    ///
    /// Critical: the scope's payload (e.g. `t` in `.pageType(let t)`) is a
    /// snapshot taken when the popover opened. Reading `t.properties`
    /// directly would render stale state after any in-popover mutation —
    /// delete / add / rename / duplicate all write through the manager
    /// then leave this list re-rendering against the original snapshot.
    /// Always extract the stable type ID and re-query the manager.
    private func resolvedProperties() -> [PropertyDefinition] {
        guard let typeID = scopeTypeID() else { return [] }
        let resolved =
            pageTypeManager.types.first(where: { $0.id == typeID })?
            .resolvedProperties(tierConfig: tierConfigManager.config) ?? []
        // Schema-only: reserved/built-in columns (tiers + Modified + the rest)
        // are non-editable, so they're excluded from this list. Their per-view
        // visibility lives in the Layout pane's eye-list.
        return resolved.filter { !ReservedPropertyID.isReserved($0.id) }
    }

    private func scopeTypeID() -> String? { scope.schemaTypeID }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: PUI.Spacing.lg) {
            Image(systemName: "list.bullet.rectangle")
                .font(PUI.Typography.Fixed.f26)
                .foregroundStyle(.tertiary)
            Text(searchQuery.isEmpty ? "No properties yet" : "No matches")
                .font(.callout)
                .foregroundStyle(.secondary)
            if searchQuery.isEmpty {
                Text("Use **+ New property** below to add the first one.")
                    .font(PUI.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, PUI.Spacing.xxxl)
            }
        }
        // Finite (not maxHeight: .infinity) so it measures cleanly inside the
        // container's scroll region; minHeight gives it presence and floors the
        // pane to PUI.Pane.minHeight.
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(.vertical, PUI.Spacing.xxxl)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        Button {
            path.append(.propertyTypePicker)
        } label: {
            HStack(spacing: PUI.Spacing.md) {
                Image(systemName: "plus")
                    .font(PUI.Icon.plus)
                    .frame(width: PUI.Icon.leadingFrame)
                Text("New property")
                    .font(PUI.Typography.row)
                Spacer()
            }
            .padding(.horizontal, PUI.Row.paddingHorizontal)
            .padding(.vertical, PUI.Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PropertyRow

private struct PropertyRow: View {
    let definition: PropertyDefinition
    let onTap: () -> Void

    private var isReserved: Bool {
        ReservedPropertyID.isReserved(definition.id)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: PUI.Row.interSpacing) {
                Image(systemName: definition.displayIcon)
                    .font(PUI.Icon.leading)
                    .foregroundStyle(isReserved ? .tertiary : .primary)
                    .frame(width: PUI.Icon.leadingFrame)

                VStack(alignment: .leading, spacing: PUI.Spacing.xxs) {
                    HStack(spacing: PUI.Spacing.xs) {
                        Text(definition.name)
                            .font(PUI.Typography.row)
                            .foregroundStyle(isReserved ? .secondary : .primary)
                            .lineLimit(1)
                        if isReserved {
                            Image(systemName: "lock.fill")
                                .font(PUI.Icon.lock)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(definition.type.displayName)
                        .font(PUI.Typography.rowSubtitle)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if !isReserved {
                    Image(systemName: "chevron.right")
                        .font(PUI.Icon.chevron)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, PUI.Row.paddingHorizontal)
            .padding(.vertical, PUI.Row.paddingVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isReserved)
        .help(isReserved ? "Built-in property — not editable" : "")
    }
}
