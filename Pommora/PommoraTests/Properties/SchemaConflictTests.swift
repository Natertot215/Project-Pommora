import Foundation
import Testing

@testable import Pommora

@Suite("SchemaConflictTests")
struct SchemaConflictTests {

    // MARK: - Helpers

    private func makeDef(id: String, name: String, type: PropertyType) -> PropertyDefinition {
        PropertyDefinition(id: id, name: name, type: type)
    }

    private func makeItem(properties: [String: PropertyValue]) -> Item {
        let now = Date()
        return Item(
            id: ULID.generate(),
            title: "TestItem",
            icon: nil,
            description: "",
            tier1: [],
            tier2: [],
            tier3: [],
            properties: properties,
            createdAt: now,
            modifiedAt: now
        )
    }

    // MARK: - Test 1: detectsRemovedProperty

    @Test("detectDrift surfaces removed property ID as a name from originalSchema")
    func detectsRemovedProperty() {
        let propID = "prop_REMOVED"
        let originalSchema = [makeDef(id: propID, name: "Priority", type: .number)]
        let freshSchema: [PropertyDefinition] = []  // property deleted on disk

        let editingProperties: [String: PropertyValue] = [propID: .number(42)]

        let result = SchemaConflictDetector.detectDrift(
            editingProperties: editingProperties,
            freshSchema: freshSchema,
            originalSchema: originalSchema
        )

        #expect(result.removed == ["Priority"])
        #expect(result.typeChanged == [])
    }

    // MARK: - Test 2: detectsTypeChange

    @Test("detectDrift surfaces type-changed property name when type differs between fresh and value")
    func detectsTypeChange() {
        let propID = "prop_CHANGED"
        let originalSchema = [makeDef(id: propID, name: "Score", type: .number)]
        // On disk someone changed the property type to checkbox while editor was open
        let freshSchema = [makeDef(id: propID, name: "Score", type: .checkbox)]

        // Editor still holds a .number value for this property
        let editingProperties: [String: PropertyValue] = [propID: .number(99)]

        let result = SchemaConflictDetector.detectDrift(
            editingProperties: editingProperties,
            freshSchema: freshSchema,
            originalSchema: originalSchema
        )

        #expect(result.removed == [])
        #expect(result.typeChanged == ["Score"])
    }

    // MARK: - Test 3: cleanSchemaProducesNoDrift

    @Test("detectDrift returns empty arrays when in-memory matches fresh schema")
    func cleanSchemaProducesNoDrift() {
        let propID = "prop_CLEAN"
        let schema = [makeDef(id: propID, name: "Tag", type: .select)]

        let editingProperties: [String: PropertyValue] = [propID: .select("active")]

        let result = SchemaConflictDetector.detectDrift(
            editingProperties: editingProperties,
            freshSchema: schema,
            originalSchema: schema
        )

        #expect(result.removed.isEmpty)
        #expect(result.typeChanged.isEmpty)
    }

    // MARK: - Test 4: saveValidSubsetFiltersStaleEntries

    @Test("filterToValidSubset drops keys not in fresh schema or with incompatible types")
    func saveValidSubsetFiltersStaleEntries() {
        let validPropID = "prop_VALID"
        let stalePropID = "prop_STALE"

        let freshSchema = [makeDef(id: validPropID, name: "Notes", type: .select)]

        let editingProperties: [String: PropertyValue] = [
            validPropID: .select("done"),
            stalePropID: .number(7),  // stale: schema removed this ID
        ]

        let filtered = SchemaConflictDetector.filterToValidSubset(
            editingProperties: editingProperties,
            freshSchema: freshSchema
        )

        #expect(filtered[validPropID] == .select("done"))
        #expect(filtered[stalePropID] == nil)
        #expect(filtered.count == 1)
    }
}
