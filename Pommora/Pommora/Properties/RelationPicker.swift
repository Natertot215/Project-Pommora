import SwiftUI

/// Scope-aware relation picker. Uses `IndexQuery.entitiesByScope(_:)` to load
/// the candidate list from SQLite. Relations are always multi-pick: selections
/// accumulate; tapping a selected entity removes it (chip-removal semantics).
/// Nil `index` renders an empty-state placeholder without crashing.
struct RelationPicker: View {
    @Binding var selectedIDs: [String]
    let scope: PropertyDefinition.RelationTarget
    let index: PommoraIndex?
    let onSelect: ([String]) -> Void

    @State private var loadedEntities: [EntityRef] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if index == nil {
                emptyState("No index available")
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if loadedEntities.isEmpty {
                emptyState("No entities found")
            } else {
                pickerList
            }
        }
        .task {
            await loadEntities()
        }
    }

    // MARK: - Subviews

    private var pickerList: some View {
        RelationPickerList(
            entities: loadedEntities,
            selectedIDs: selectedIDs,
            onTap: { entityID, wasSelected in
                let updated = computeSelection(
                    id: entityID,
                    wasSelected: wasSelected,
                    current: selectedIDs
                )
                selectedIDs = updated
                onSelect(updated)
            }
        )
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Selection logic

    /// Pure selection computation — takes current selection array, returns the
    /// new array after toggling `id`. Relations are always multi-pick.
    /// Exposed (non-private) so tests can call it directly without a live SwiftUI button tap.
    func computeSelection(id: String, wasSelected: Bool, current: [String]) -> [String] {
        wasSelected ? current.filter { $0 != id } : current + [id]
    }

    // MARK: - Data loading

    private func loadEntities() async {
        guard let idx = index else { return }
        isLoading = true
        do {
            loadedEntities = try await IndexQuery(idx).entitiesByScope(scope)
        } catch {
            loadedEntities = []
        }
        isLoading = false
    }
}

// MARK: - RelationPickerList (isolated from Binding + GRDB overloads)

/// Isolated sub-view for the entity list. Receives plain value types so the
/// compiler does not confuse GRDB's `@dynamicMemberLookup` / `==` overloads
/// with SwiftUI's `Binding` subscript inside the ForEach closure.
private struct RelationPickerList: View {
    let entities: [EntityRef]
    let selectedIDs: [String]
    let onTap: (String, Bool) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(entityRows, id: \.rowID) { row in
                    RelationPickerRow(
                        row: row,
                        isSelected: selectedIDs.containsID(row.rowID),
                        onTap: onTap
                    )
                }
            }
        }
    }

    private var entityRows: [RelationEntityRow] {
        entities.map { RelationEntityRow(entity: $0) }
    }
}

// MARK: - RelationPickerRow

private struct RelationPickerRow: View {
    let row: RelationEntityRow
    let isSelected: Bool
    let onTap: (String, Bool) -> Void

    var body: some View {
        Button {
            onTap(row.rowID, isSelected)
        } label: {
            HStack {
                Image(systemName: row.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(row.title)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - RelationEntityRow (plain struct, no GRDB conformances)

/// Plain value type wrapping an EntityRef for display. No GRDB conformances,
/// so ForEach can resolve `Identifiable` and `==` unambiguously.
private struct RelationEntityRow: Identifiable {
    let id = UUID()      // ForEach identity — stable per render pass
    let rowID: String    // entity ID passed back to onTap
    let title: String
    let icon: String

    init(entity: EntityRef) {
        self.rowID = entity.id
        self.title = entity.title.isEmpty ? "Untitled" : entity.title
        self.icon = Self.iconName(entity.kind)
    }

    private static func iconName(_ kind: EntityKind) -> String {
        switch kind {
        case .page:           return "doc.text"
        case .item:           return "tray"
        case .agendaTask:     return "checkmark.circle"
        case .agendaEvent:    return "calendar"
        case .pageType:       return "folder"
        case .itemType:       return "folder"
        case .pageCollection: return "folder.badge.gearshape"
        case .itemCollection: return "folder.badge.gearshape"
        case .space:          return "building.2"
        case .topic:          return "tag"
        case .project:        return "briefcase"
        }
    }
}

// MARK: - [String] containsID helper

private extension Array where Element == String {
    /// Avoids GRDB's `SQLSpecificExpressible`-based `contains` overload by
    /// explicitly using `first(where:)` with a closure comparison.
    func containsID(_ id: String) -> Bool {
        first(where: { element in element == id }) != nil
    }
}
