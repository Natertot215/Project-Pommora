import Foundation

/// Value type that describes the four user-creatable relation-target sections,
/// in the canonical display order: Items, Vaults, Events, Tasks.
///
/// Legacy targets (pageCollection / itemCollection) and the internal contextTier
/// are intentionally absent — they are not offered in the relation editor UI.
struct RelationTargetCatalog {

    // MARK: - Row

    struct Row: Identifiable, Equatable {
        let id: String                                   // target ID or ReservedTypeID for singletons
        let label: String                                // display title
        let icon: String                                 // SF Symbol name
        let target: PropertyDefinition.RelationTarget
    }

    // MARK: - Section

    struct Section: Identifiable {
        var id: String { header }
        let header: String
        let rows: [Row]
    }

    // MARK: - Inputs

    let pageTypes: [PageType]
    let itemTypes: [ItemType]

    /// Optional header overrides — callers may pass SettingsManager labels;
    /// defaults match the UI vocabulary for each side.
    var itemsHeader: String = "Items"
    var vaultsHeader: String = "Vaults"
    var eventsHeader: String = "Events"
    var tasksHeader: String = "Tasks"

    // MARK: - sections()

    /// Returns the four sections in canonical order: Items, Vaults, Events, Tasks.
    func sections() -> [Section] {
        let itemRows: [Row] = itemTypes.map { it in
            Row(
                id: it.id,
                label: it.title,
                icon: it.icon ?? "shippingbox",
                target: .itemType(it.id)
            )
        }

        let vaultRows: [Row] = pageTypes.map { pt in
            Row(
                id: pt.id,
                label: pt.title,
                icon: pt.icon ?? "books.vertical",
                target: .pageType(pt.id)
            )
        }

        let eventsRow = Row(
            id: ReservedTypeID.agendaEvents,
            label: eventsHeader,
            icon: "calendar",
            target: .agendaEvents
        )

        let tasksRow = Row(
            id: ReservedTypeID.agendaTasks,
            label: tasksHeader,
            icon: "checkmark.circle",
            target: .agendaTasks
        )

        return [
            Section(header: itemsHeader, rows: itemRows),
            Section(header: vaultsHeader, rows: vaultRows),
            Section(header: eventsHeader, rows: [eventsRow]),
            Section(header: tasksHeader, rows: [tasksRow]),
        ]
    }

    // MARK: - resolve(_:)

    /// Returns the Row matching `target` by scanning all sections, or nil if
    /// the target is nil, legacy, or internal (contextTier).
    func resolve(_ target: PropertyDefinition.RelationTarget?) -> Row? {
        guard let target else { return nil }
        return sections()
            .flatMap(\.rows)
            .first(where: { row in row.target == target })
    }
}
