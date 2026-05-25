import Foundation
import Testing

@testable import Pommora

/// Tests for `PropertyPanelViewModel` — the business logic backing `PropertyPanel`.
/// Tests drive the view-model directly (J.5 pattern) without SwiftUI rendering.
@Suite("PropertyPanelTests")
@MainActor
struct PropertyPanelTests {

    // MARK: - Helpers

    private func makeAutoManaged() -> AutoManagedFields {
        AutoManagedFields(
            id: "01HTEST",
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 60)
        )
    }

    private func makeDef(id: String, name: String, type: PropertyType = .number) -> PropertyDefinition {
        PropertyDefinition(id: id, name: name, type: type)
    }

    private func makeVM(
        schema: [PropertyDefinition] = [],
        values: [String: PropertyValue] = [:],
        tier1: [String] = [],
        tier2: [String] = [],
        tier3: [String] = []
    ) -> (vm: PropertyPanelViewModel, valueChanges: () -> [(String, PropertyValue)], tierChanges: () -> [(Int, [String])]) {
        var capturedValues: [(String, PropertyValue)] = []
        var capturedTiers: [(Int, [String])] = []
        let vm = PropertyPanelViewModel(
            schema: schema,
            values: values,
            tier1: tier1,
            tier2: tier2,
            tier3: tier3,
            autoManaged: makeAutoManaged(),
            onValueChange: { id, val in capturedValues.append((id, val)) },
            onTierChange: { tier, ids in capturedTiers.append((tier, ids)) }
        )
        return (vm, { capturedValues }, { capturedTiers })
    }

    // MARK: - Test 1: empty schema has no schema rows, only tier rows

    @Test("Empty schema: no schema rows, tier rows always present")
    func emptySchemaRendersOnlyTiers() {
        let (vm, _, _) = makeVM(schema: [])
        #expect(vm.schema.isEmpty)
        // Tier bindings are accessible
        #expect(vm.tier1 == [])
        #expect(vm.tier2 == [])
        #expect(vm.tier3 == [])
        // totalRowCount = 0 schema + 3 tier rows
        #expect(vm.totalRowCount == 3)
    }

    // MARK: - Test 2: schema with 3 properties = 3 schema rows + 3 tier rows

    @Test("Schema with 3 properties: totalRowCount == 6")
    func schemaWithThreeProperties() {
        let schema = [
            makeDef(id: "prop_1", name: "Name"),
            makeDef(id: "prop_2", name: "Count"),
            makeDef(id: "prop_3", name: "Done", type: .checkbox),
        ]
        let (vm, _, _) = makeVM(schema: schema)
        #expect(vm.schema.count == 3)
        #expect(vm.totalRowCount == 6)
        #expect(vm.hasSchema)
    }

    // MARK: - Test 3: tier1/2/3 always rendered even when arrays are empty

    @Test("Tier arrays are accessible even when empty — no crash or nil")
    func tiersAlwaysRendered() {
        let (vm, _, _) = makeVM(tier1: [], tier2: [], tier3: [])
        #expect(vm.tier1 == [])
        #expect(vm.tier2 == [])
        #expect(vm.tier3 == [])
    }

    // MARK: - Test 4: auto-managed section is collapsed by default

    @Test("Auto-managed section is collapsed by default")
    func autoManagedCollapsedByDefault() {
        let (vm, _, _) = makeVM()
        #expect(vm.autoManagedExpanded == false)
    }

    // MARK: - Test 5: value change calls onValueChange with correct property ID

    @Test("handleValueChange fires onValueChange with correct propertyID and value")
    func valueChangeCallsCallback() {
        let schema = [makeDef(id: "prop_abc", name: "Score")]
        let (vm, valueChanges, _) = makeVM(schema: schema)

        vm.handleValueChange("prop_abc", .number(42.0))

        let changes = valueChanges()
        #expect(changes.count == 1)
        #expect(changes[0].0 == "prop_abc")
        #expect(changes[0].1 == .number(42.0))
    }

    // MARK: - Test 6: value change updates local values dict

    @Test("handleValueChange updates local values dictionary")
    func valueChangeUpdatesLocalDict() {
        let (vm, _, _) = makeVM()
        vm.handleValueChange("prop_xyz", .checkbox(true))
        #expect(vm.values["prop_xyz"] == .checkbox(true))
    }

    // MARK: - Test 7: tier change fires onTierChange with correct tier number

    @Test("handleTierChange fires onTierChange with tier number and IDs")
    func tierChangeCallsCallback() {
        let (vm, _, tierChanges) = makeVM()
        let ids = ["01HA", "01HB"]
        vm.handleTierChange(1, ids)

        let changes = tierChanges()
        #expect(changes.count == 1)
        #expect(changes[0].0 == 1)
        #expect(changes[0].1 == ids)
        #expect(vm.tier1 == ids)
    }

    // MARK: - Test 8: out-of-range tier number is ignored

    @Test("handleTierChange with invalid tier number is a no-op")
    func tierChangeInvalidTierIgnored() {
        let (vm, _, tierChanges) = makeVM()
        vm.handleTierChange(99, ["01HA"])
        // onTierChange still called; state not changed for tiers 1-3
        // (callback is fired, but tier1/2/3 unchanged)
        #expect(vm.tier1 == [])
        #expect(vm.tier2 == [])
        #expect(vm.tier3 == [])
        _ = tierChanges  // suppress unused warning
    }
}
