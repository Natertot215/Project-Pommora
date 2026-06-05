import Foundation
import Testing

@testable import Pommora

/// Tests for `PropertiesPulldownViewModel` — the lazy property surface (Phase J.13).
/// Tests drive the view-model directly without SwiftUI rendering (J.5 pattern).
@Suite("PropertiesPulldownTests")
@MainActor
struct PropertiesPulldownTests {

    // MARK: - Helpers

    private func makeAutoManaged() -> AutoManagedFields {
        AutoManagedFields(
            id: "01HTEST",
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 60)
        )
    }

    private func makeDef(
        id: String,
        name: String,
        type: PropertyType = .number
    ) -> PropertyDefinition {
        PropertyDefinition(id: id, name: name, type: type)
    }

    private func makeVM(
        schema: [PropertyDefinition] = [],
        values: [String: PropertyValue] = [:],
        tier1: [String] = [],
        tier2: [String] = [],
        tier3: [String] = []
    ) -> PropertiesPulldownViewModel {
        PropertiesPulldownViewModel(
            schema: schema,
            values: values,
            tier1: tier1,
            tier2: tier2,
            tier3: tier3,
            autoManaged: makeAutoManaged(),
            onValueChange: { _, _ in },
            onTierChange: { _, _ in }
        )
    }

    // MARK: - Test 1: default closed

    @Test("PropertiesPulldown is closed by default")
    func defaultClosed() {
        let vm = makeVM()
        #expect(vm.isExpanded == false)
    }

    // MARK: - Test 2: lazy — only populated properties show

    @Test("Lazy: 3 schema entries with 1 populated → 1 visible row")
    func lazyPopulatedOnly() {
        let schema = [
            makeDef(id: "prop_1", name: "A"),
            makeDef(id: "prop_2", name: "B"),
            makeDef(id: "prop_3", name: "C"),
        ]
        let values: [String: PropertyValue] = [
            "prop_1": .number(42.0),  // populated
            "prop_2": .null,           // null → not shown
            // prop_3: absent → not shown
        ]
        let vm = makeVM(schema: schema, values: values)
        #expect(vm.populatedProperties.count == 1)
        #expect(vm.populatedProperties[0].id == "prop_1")
    }

    // MARK: - Test 3: empty state visible when fully empty

    @Test("Empty state: no populated properties yields empty populatedProperties + count == 0")
    func emptyStateAlwaysVisible() {
        let schema = [
            makeDef(id: "prop_1", name: "Foo"),
            makeDef(id: "prop_2", name: "Bar"),
        ]
        let vm = makeVM(schema: schema, values: [:])
        #expect(vm.populatedProperties.isEmpty)
        #expect(vm.populatedCount == 0)
        // tier1/2/3 also empty
        #expect(vm.showTier1 == false)
        #expect(vm.showTier2 == false)
        #expect(vm.showTier3 == false)
    }

    // MARK: - Test 4: addableProperties excludes built-ins and .lastEditedTime

    @Test("addableProperties excludes reserved IDs and lastEditedTime")
    func addablePropertiesExcludesBuiltins() {
        let schema: [PropertyDefinition] = [
            makeDef(id: "prop_user", name: "Custom", type: .number),
            makeDef(id: "_status", name: "Status", type: .status),
            makeDef(id: "_tier1", name: "Tier 1", type: .relation),
            makeDef(id: "prop_last_edited", name: "Last Edited", type: .lastEditedTime),
        ]
        let vm = makeVM(schema: schema, values: [:])
        let addable = vm.addableProperties

        // Only prop_user should be addable
        #expect(addable.count == 1)
        #expect(addable[0].id == "prop_user")

        // Reserved IDs excluded
        #expect(addable.first(where: { $0.id == "_status" }) == nil)
        #expect(addable.first(where: { $0.id == "_tier1" }) == nil)
        // lastEditedTime excluded (L15)
        #expect(addable.first(where: { $0.type == .lastEditedTime }) == nil)
    }

    // MARK: - Test 5: already-populated props excluded from addableProperties

    @Test("addableProperties excludes already-populated properties")
    func addableExcludesPopulated() {
        let schema = [
            makeDef(id: "prop_a", name: "A"),
            makeDef(id: "prop_b", name: "B"),
        ]
        let values: [String: PropertyValue] = ["prop_a": .number(1.0)]
        let vm = makeVM(schema: schema, values: values)
        let addable = vm.addableProperties

        // prop_a is populated → not addable; prop_b is empty → addable
        #expect(addable.count == 1)
        #expect(addable[0].id == "prop_b")
    }

    // MARK: - Test 6: tier lazy visibility

    @Test("Tier visibility is lazy: show only non-empty tiers")
    func tierVisibilityIsLazy() {
        let vm = makeVM(tier1: ["01HA"], tier2: [], tier3: [])
        #expect(vm.showTier1 == true)
        #expect(vm.showTier2 == false)
        #expect(vm.showTier3 == false)
    }

    // MARK: - Test 7: addProperty sets null value in dict

    @Test("addProperty inserts a .null entry for the given propertyID")
    func addPropertyInsertsNull() {
        let vm = makeVM()
        vm.addProperty(id: "prop_new")
        #expect(vm.values["prop_new"] == .null)
    }

    // MARK: - Test 8: handleValueChange removes prop from populatedProperties when set to null

    @Test("Setting a value to .null removes it from populatedProperties")
    func settingNullRemovesFromPopulated() {
        let schema = [makeDef(id: "prop_x", name: "X")]
        let vm = makeVM(schema: schema, values: ["prop_x": .checkbox(true)])
        #expect(vm.populatedProperties.count == 1)

        vm.handleValueChange("prop_x", .null)
        #expect(vm.populatedProperties.count == 0)
    }
}
