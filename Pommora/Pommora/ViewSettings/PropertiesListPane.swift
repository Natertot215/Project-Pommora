import SwiftUI

/// View Settings → Edit Properties → list of every property on the active
/// Type's schema. Reserved properties (per `ReservedPropertyID.isReserved`)
/// render with a lock badge + disabled chevron + tooltip; user-defined
/// properties push to `EditPropertyPane` via the chevron.
///
/// Footer "+ New property" button pushes `PropertyTypePickerPane` so the
/// user picks a type before naming + configuring (Task 10 routing).
///
/// Schema ownership: properties live on PageType / ItemType. For Collection
/// scopes the pane resolves the parent Type via the manager (PageType /
/// ItemType manager looked up from @Environment).
///
/// Chrome routed through shared `PaneHeader` + `PUI` tokens for uniformity
/// with every other View Settings sub-pane.
struct PropertiesListPane: View {
    let scope: ViewSettingsScope
    @Binding var path: [ViewSettingsRoute]

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(ItemTypeManager.self) private var itemTypeManager

    @State private var searchQuery: String = ""

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(path: $path, title: "Edit Properties")
            propertyList
                .frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: PUI.Pane.width, height: PUI.Pane.height)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - List

    @ViewBuilder
    private var propertyList: some View {
        let props = filteredProperties()
        if props.isEmpty {
            emptyState
        } else {
            ScrollView {
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
    }

    private func filteredProperties() -> [PropertyDefinition] {
        let all = resolvedProperties()
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Resolves the parent Type's properties for any storage scope.
    /// Collections inherit their parent Type's schema (per Properties.md).
    private func resolvedProperties() -> [PropertyDefinition] {
        switch scope {
        case .pageType(let t):
            return t.properties
        case .itemType(let t):
            return t.properties
        case .pageCollection(let c):
            return pageTypeManager.types.first(where: { $0.id == c.typeID })?.properties ?? []
        case .itemCollection(let c):
            return itemTypeManager.types.first(where: { $0.id == c.typeID })?.properties ?? []
        default:
            return []
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: PUI.Spacing.lg) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 26))
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Image(systemName: definition.icon ?? definition.type.pickerIcon)
                    .font(PUI.Icon.leading)
                    .foregroundStyle(isReserved ? .tertiary : .primary)
                    .frame(width: PUI.Icon.leadingFrame)

                VStack(alignment: .leading, spacing: 2) {
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
