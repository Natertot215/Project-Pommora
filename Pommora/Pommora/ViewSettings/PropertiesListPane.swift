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
/// Task 9 ships the list + lock-badge rendering + searchable + + New property
/// footer push. Search filtering of long lists is good-to-have; reserved-
/// property rendering is required.
struct PropertiesListPane: View {
    let scope: ViewSettingsScope
    @Binding var path: [ViewSettingsRoute]

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(ItemTypeManager.self) private var itemTypeManager

    @State private var searchQuery: String = ""

    var body: some View {
        VStack(spacing: 0) {
            inlineHeader
            Divider()
            propertyList
                .frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 300, height: 360)
        .navigationBarBackButtonHidden(true)
        // NOTE: `.toolbar(.hidden)` was tried first but on macOS suppresses the
        // entire pushed pane, not just the chrome. Dropped; dark navigation-bar
        // band returns briefly. Full chrome unification slated for next-session
        // redesign.
    }

    // MARK: - Inline header (matches StorageMenuRoot styling)

    @ViewBuilder
    private var inlineHeader: some View {
        HStack(spacing: 8) {
            Button {
                if !path.isEmpty { path.removeLast() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back")

            Text("Edit Properties")
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 8)
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
                        Divider().padding(.leading, 40)
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
        VStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(searchQuery.isEmpty ? "No properties yet" : "No matches")
                .font(.callout)
                .foregroundStyle(.secondary)
            if searchQuery.isEmpty {
                Text("Use **+ New property** below to add the first one.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
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
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                Text("New property")
                    .font(.callout)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
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
            HStack(spacing: 10) {
                Image(systemName: definition.icon ?? definition.type.pickerIcon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isReserved ? .tertiary : .primary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(definition.name)
                            .font(.callout)
                            .foregroundStyle(isReserved ? .secondary : .primary)
                            .lineLimit(1)
                        if isReserved {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(definition.type.displayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if !isReserved {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isReserved)
        .help(isReserved ? "Built-in property — not editable" : "")
    }
}
