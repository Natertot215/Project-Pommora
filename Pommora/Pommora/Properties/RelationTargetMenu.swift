import SwiftUI

/// Two-level `Menu` for picking a relation target.
///
/// Top-level structure mirrors `RelationTargetCatalog.sections()`:
/// - **Items** → nested submenu (one button per ItemType; disabled "No Items" if empty)
/// - **Vaults** → nested submenu (one button per PageType; disabled "No Vaults" if empty)
/// - **Events** → direct top-level button (singleton)
/// - **Tasks**  → direct top-level button (singleton)
///
/// Per-row rendering is isolated into `TargetMenuRow` (plain value types) to avoid
/// GRDB `String` overload pollution (SQLSpecificExpressible / `==` ambiguity) inside
/// `@ViewBuilder` closures — see branch quirk #13.
struct RelationTargetMenu: View {
    let catalog: RelationTargetCatalog
    @Binding var selection: PropertyDefinition.RelationTarget?

    var body: some View {
        Menu {
            menuContent
        } label: {
            buttonLabel
        }
    }

    // MARK: - Menu label

    private var buttonLabel: some View {
        Group {
            if let row = catalog.resolve(selection) {
                TargetMenuRow(label: row.label, icon: row.icon, isSelected: false)
            } else {
                Text("Select target")
            }
        }
    }

    // MARK: - Menu content

    @ViewBuilder
    private var menuContent: some View {
        let allSections = catalog.sections()

        // Items section — always a nested submenu
        if let itemsSection = allSections.first(where: { $0.header == catalog.itemsHeader }) {
            Menu(catalog.itemsHeader) {
                itemsSubmenuContent(rows: itemsSection.rows)
            }
        }

        // Vaults section — always a nested submenu
        if let vaultsSection = allSections.first(where: { $0.header == catalog.vaultsHeader }) {
            Menu(catalog.vaultsHeader) {
                vaultsSubmenuContent(rows: vaultsSection.rows)
            }
        }

        // Events — direct top-level button (singleton)
        singletonButton(row: Row(
            id: ReservedTypeID.agendaEvents,
            label: catalog.eventsHeader,
            icon: "calendar",
            target: .agendaEvents
        ))

        // Tasks — direct top-level button (singleton)
        singletonButton(row: Row(
            id: ReservedTypeID.agendaTasks,
            label: catalog.tasksHeader,
            icon: "checkmark.circle",
            target: .agendaTasks
        ))
    }

    // MARK: - Submenu helpers

    @ViewBuilder
    private func itemsSubmenuContent(rows: [RelationTargetCatalog.Row]) -> some View {
        if rows.isEmpty {
            Text("No Items").disabled(true)
        } else {
            ForEach(rows) { row in
                submenuButton(row: row)
            }
        }
    }

    @ViewBuilder
    private func vaultsSubmenuContent(rows: [RelationTargetCatalog.Row]) -> some View {
        if rows.isEmpty {
            Text("No Vaults").disabled(true)
        } else {
            ForEach(rows) { row in
                submenuButton(row: row)
            }
        }
    }

    // MARK: - Button factories

    private func submenuButton(row: RelationTargetCatalog.Row) -> some View {
        let isSelected = selection == row.target
        return Button {
            selection = row.target
        } label: {
            TargetMenuRow(label: row.label, icon: row.icon, isSelected: isSelected)
        }
    }

    private func singletonButton(row: Row) -> some View {
        let isSelected = selection == row.target
        return Button {
            selection = row.target
        } label: {
            TargetMenuRow(label: row.label, icon: row.icon, isSelected: isSelected)
        }
    }
}

// MARK: - TargetMenuRow (isolated plain-value sub-view)

/// Renders a single row label inside a menu button.
/// Isolated from `@Binding` and GRDB conformances to avoid `==` overload ambiguity.
private struct TargetMenuRow: View {
    let label: String
    let icon: String
    let isSelected: Bool

    var body: some View {
        Label {
            HStack {
                Text(label)
                if isSelected {
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
        } icon: {
            Image(systemName: icon)
        }
    }
}

// MARK: - Local Row alias (avoids repeating the full qualified name in helpers)

private typealias Row = RelationTargetCatalog.Row
