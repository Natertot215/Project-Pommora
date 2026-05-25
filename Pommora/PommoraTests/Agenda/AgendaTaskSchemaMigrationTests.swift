import Foundation
import Testing

@testable import Pommora

@Suite("AgendaTaskSchemaMigration")
struct AgendaTaskSchemaMigrationTests {

    // MARK: - Test 1: legacy shape migrates to PropertyDefinition

    /// Decodes a JSON blob using the old `Property` nested shape and verifies it
    /// is transparently migrated to `[PropertyDefinition]` with correctly minted IDs:
    /// `_type` for builtin properties, `prop_<ulid>` for user-defined ones.
    @Test("legacy Property shape migrates to PropertyDefinition with minted IDs")
    func legacyShapeMigratesToPropertyDefinition() throws {
        let legacyJSON = """
            {
                "schemaVersion": 1,
                "icon": "checkmark.circle",
                "properties": [
                    {
                        "name": "type",
                        "type": "select",
                        "options": [
                            {"value": "Task", "label": "Task", "color": "blue"},
                            {"value": "To-Do", "label": "To-Do", "color": "yellow"},
                            {"value": "Phase", "label": "Phase", "color": "purple"}
                        ],
                        "builtin": true,
                        "default": "Task"
                    },
                    {
                        "name": "priority",
                        "type": "number",
                        "builtin": false
                    }
                ],
                "views": [],
                "modified_at": 0
            }
            """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let schema = try decoder.decode(AgendaTaskSchema.self, from: Data(legacyJSON.utf8))

        #expect(schema.properties.count == 2)

        // Builtin "type" property must get reserved ID "_type"
        let typeProp = schema.properties.first { $0.name == "type" }
        #expect(typeProp != nil)
        #expect(typeProp?.id == "_type")
        #expect(typeProp?.type == .select)

        // User-defined "priority" property must get a fresh prop_ ID
        let priorityProp = schema.properties.first { $0.name == "priority" }
        #expect(priorityProp != nil)
        #expect(priorityProp?.id.hasPrefix("prop_") == true)
        #expect(priorityProp?.type == .number)
    }

    // MARK: - Test 2: defaultSeed() injects exactly one property — _status

    /// G.1: `defaultSeed()` now returns a schema with exactly one property:
    /// `_status` (id), `"Status"` (name), `.status` (type),
    /// `PropertyDefinition.StatusGroup.defaultSeed()` (statusGroups).
    @Test("defaultSeed returns exactly one property: _status with Status type and defaultSeed groups")
    func defaultSeedInjectsStatusProperty() {
        let schema = AgendaTaskSchema.defaultSeed()

        // Exactly one property — no legacy _type
        #expect(schema.properties.count == 1)
        #expect(schema.properties.contains { $0.id == "_type" } == false)

        let statusProp = schema.properties.first
        #expect(statusProp?.id == "_status")
        #expect(statusProp?.name == "Status")
        #expect(statusProp?.type == .status)

        // StatusGroups must be present and match the default seed
        let expected = PropertyDefinition.StatusGroup.defaultSeed()
        let actual = statusProp?.statusGroups ?? []
        #expect(actual.count == expected.count)
        #expect(actual.map(\.id) == expected.map(\.id))
        #expect(actual.map(\.label) == expected.map(\.label))
    }

    // MARK: - Test 3: round-trip preserves the new shape

    /// Encodes a migrated schema then decodes again — shape must be stable (no
    /// re-migration from legacy path on second decode, IDs preserved).
    @Test("round-trip encode → decode preserves PropertyDefinition shape and IDs")
    func roundTripPreservesNewShape() throws {
        let original = AgendaTaskSchema.defaultSeed()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(AgendaTaskSchema.self, from: data)

        #expect(decoded.properties.count == original.properties.count)
        for (orig, rt) in zip(original.properties, decoded.properties) {
            #expect(rt.id == orig.id)
            #expect(rt.name == orig.name)
            #expect(rt.type == orig.type)
        }
    }
}
