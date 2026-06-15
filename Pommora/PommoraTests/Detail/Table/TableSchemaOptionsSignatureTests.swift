import Foundation
import Testing

@testable import Pommora

/// Covers `tableSchemaOptionsSignature(of:)` — the hash that gates the table's
/// `reloadData()` call when select/status options change.
///
/// Root cause verified: before this fix, the reload signature in
/// `ViewOutlineTable.Coordinator.reload(_:)` did not include option content,
/// so adding a new Select or Status option left the signature unchanged, skipped
/// `NSOutlineView.reloadData()`, and made new options invisible in ChipDropdown
/// until a restart.
@Suite("TableSchemaOptionsSignature") struct TableSchemaOptionsSignatureTests {

    // MARK: - Select property

    @Test("Select — adding an option changes the signature")
    func selectOptionAddedChangesSignature() {
        let base = PropertyDefinition(
            id: "prop_a",
            name: "Status",
            type: .select,
            selectOptions: [.init(value: "opt1", label: "Option 1", color: nil)]
        )
        let extended = PropertyDefinition(
            id: "prop_a",
            name: "Status",
            type: .select,
            selectOptions: [
                .init(value: "opt1", label: "Option 1", color: nil),
                .init(value: "opt2", label: "Option 2", color: nil),
            ]
        )
        #expect(tableSchemaOptionsSignature(of: [base]) != tableSchemaOptionsSignature(of: [extended]))
    }

    @Test("Select — unchanged options produce the same signature")
    func selectUnchangedIsStable() {
        let def = PropertyDefinition(
            id: "prop_a",
            name: "Color",
            type: .select,
            selectOptions: [.init(value: "red", label: "Red", color: .red)]
        )
        #expect(tableSchemaOptionsSignature(of: [def]) == tableSchemaOptionsSignature(of: [def]))
    }

    // MARK: - Status property

    @Test("Status — adding an option to a group changes the signature")
    func statusOptionAddedChangesSignature() {
        var baseGroups = PropertyDefinition.StatusGroup.defaultSeed()
        let extendedGroups: [PropertyDefinition.StatusGroup] = {
            var groups = baseGroups
            groups[0].options.append(
                .init(value: "waiting", label: "Waiting", color: nil, groupID: .upcoming)
            )
            return groups
        }()
        let base = PropertyDefinition(id: "prop_s", name: "S", type: .status, statusGroups: baseGroups)
        let extended = PropertyDefinition(id: "prop_s", name: "S", type: .status, statusGroups: extendedGroups)
        #expect(tableSchemaOptionsSignature(of: [base]) != tableSchemaOptionsSignature(of: [extended]))
    }

    // MARK: - Non-option properties

    @Test("Non-option property change does not affect signature")
    func nonOptionPropertyDoesNotAffectSignature() {
        let a = PropertyDefinition(id: "prop_n", name: "Notes", type: .number)
        let b = PropertyDefinition(id: "prop_n", name: "Notes Renamed", type: .number)
        #expect(tableSchemaOptionsSignature(of: [a]) == tableSchemaOptionsSignature(of: [b]))
    }

    // MARK: - Order independence

    @Test("Schema sort order does not affect signature — result is id-sorted")
    func schemaOrderIndependent() {
        let x = PropertyDefinition(
            id: "prop_x", name: "X", type: .select,
            selectOptions: [.init(value: "v1", label: "V1", color: nil)]
        )
        let y = PropertyDefinition(
            id: "prop_y", name: "Y", type: .select,
            selectOptions: [.init(value: "v2", label: "V2", color: nil)]
        )
        #expect(tableSchemaOptionsSignature(of: [x, y]) == tableSchemaOptionsSignature(of: [y, x]))
    }
}
