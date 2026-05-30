import SwiftUI

/// Scope-aware relation picker. Uses `IndexQuery.entitiesByTarget(_:)` to load
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

    /// Fixed panel width so the popover establishes a stable size on first
    /// render and can't collapse before the candidate list loads. (Without it,
    /// the chromeless popover sizes to the zero-size loading state and never
    /// grows when the list arrives.)
    private static let panelWidth: CGFloat = 235

    var body: some View {
        states
            .frame(width: Self.panelWidth)
            .padding(8)
            .chipDropdownPanel()
            .task { await loadEntities() }
    }

    // MARK: - State

    @ViewBuilder
    private var states: some View {
        if index == nil {
            placeholder("No index available")
        } else if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else if loadedEntities.isEmpty {
            placeholder("No matching items")
        } else {
            pickerList
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

    private func placeholder(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
            loadedEntities = try await IndexQuery(idx).entitiesByTarget(scope)
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
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(entityRows, id: \.rowID) { row in
                    RelationPickerRow(
                        row: row,
                        isSelected: selectedIDs.containsID(row.rowID),
                        onTap: onTap
                    )
                }
            }
        }
        // Cap height so long candidate lists scroll inside the panel rather
        // than growing the popover unbounded.
        .frame(maxHeight: 280)
    }

    private var entityRows: [RelationEntityRow] {
        entities.map { RelationEntityRow(entity: $0) }
    }
}

// MARK: - RelationPickerRow

/// A single candidate row: leading selection checkbox + a `RelationChip`
/// rendering the target entity's icon + title. Matches the Select/Multi-Select
/// visual family (checkbox + chip). The whole row is tappable — both the
/// checkbox and the chip area toggle the same selection via `onTap`. Mirrors
/// `ChipDropdownRow`'s checkbox-plus-pill layout (the proven pattern).
private struct RelationPickerRow: View {
    let row: RelationEntityRow
    let isSelected: Bool
    let onTap: (String, Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            PropertyCheckbox(
                isChecked: Binding(get: { isSelected }, set: { _ in onTap(row.rowID, isSelected) }),
                color: .blue,
                icon: "checkmark",
                size: 16
            )
            Button {
                onTap(row.rowID, isSelected)
            } label: {
                HStack(spacing: 4) {
                    RelationChip(icon: row.icon, title: row.title)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}

// MARK: - RelationEntityRow (plain struct, no GRDB conformances)

/// Plain value type wrapping an EntityRef for display. No GRDB conformances,
/// so ForEach can resolve `Identifiable` and `==` unambiguously.
private struct RelationEntityRow: Identifiable {
    let id = UUID()  // ForEach identity — stable per render pass
    let rowID: String  // entity ID passed back to onTap
    let title: String
    let icon: String

    init(entity: EntityRef) {
        self.rowID = entity.id
        self.title = entity.title.isEmpty ? "Untitled" : entity.title
        self.icon = Self.iconName(entity.kind)
    }

    private static func iconName(_ kind: EntityKind) -> String {
        switch kind {
        case .page: return "doc.text"
        case .item: return "tray"
        case .agendaTask: return "checkmark.circle"
        case .agendaEvent: return "calendar"
        case .pageType: return "folder"
        case .itemType: return "folder"
        case .pageCollection: return "folder.badge.gearshape"
        case .itemCollection: return "folder.badge.gearshape"
        case .space: return "building.2"
        case .topic: return "tag"
        case .project: return "briefcase"
        }
    }
}

// MARK: - [String] containsID helper

extension Array where Element == String {
    /// Avoids GRDB's `SQLSpecificExpressible`-based `contains` overload by
    /// explicitly using `first(where:)` with a closure comparison.
    fileprivate func containsID(_ id: String) -> Bool {
        first(where: { element in element == id }) != nil
    }
}
