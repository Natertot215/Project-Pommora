import Foundation
import Testing

@testable import Pommora

@Suite("AgendaEventSchemaMigration")
struct AgendaEventSchemaMigrationTests {

    // MARK: - Test 1: legacy shape migrates to PropertyDefinition

    /// Decodes a JSON blob using the old `Property` nested shape and verifies it
    /// is transparently migrated to `[PropertyDefinition]` with correctly minted IDs:
    /// `_type` for builtin properties, `prop_<ulid>` for user-defined ones.
    @Test("legacy Property shape migrates to PropertyDefinition with minted IDs")
    func legacyShapeMigratesToPropertyDefinition() throws {
        let legacyJSON = """
            {
                "schemaVersion": 1,
                "icon": "calendar",
                "properties": [
                    {
                        "name": "type",
                        "type": "select",
                        "options": [
                            {"value": "Event", "label": "Event", "color": "green"},
                            {"value": "Meeting", "label": "Meeting", "color": "blue"},
                            {"value": "Appointment", "label": "Appointment", "color": "purple"}
                        ],
                        "builtin": true,
                        "default": "Event"
                    },
                    {
                        "name": "location-tag",
                        "type": "text",
                        "builtin": false
                    }
                ],
                "views": [],
                "modified_at": 0
            }
            """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let schema = try decoder.decode(AgendaEventSchema.self, from: Data(legacyJSON.utf8))

        #expect(schema.properties.count == 2)

        // Builtin "type" property must get reserved ID "_type"
        let typeProp = schema.properties.first { $0.name == "type" }
        #expect(typeProp != nil)
        #expect(typeProp?.id == "_type")
        #expect(typeProp?.type == .select)

        // User-defined "location-tag" property must get a fresh prop_ ID
        let locationProp = schema.properties.first { $0.name == "location-tag" }
        #expect(locationProp != nil)
        #expect(locationProp?.id.hasPrefix("prop_") == true)
        #expect(locationProp?.type == .text)
    }

    // MARK: - Test 2: defaultSeed() produces _type for the built-in Select

    /// Verifies that `defaultSeed()` produces a `PropertyDefinition` with `id == "_type"`
    /// for the built-in type Select property.
    @Test("defaultSeed produces PropertyDefinition with id '_type'")
    func builtinTypePropertyKeepsIDType() {
        let schema = AgendaEventSchema.defaultSeed()
        let typeProp = schema.properties.first { $0.id == "_type" }
        #expect(typeProp != nil)
        #expect(typeProp?.name == "type")
        #expect(typeProp?.type == .select)
        let options: [PropertyDefinition.SelectOption] = typeProp?.selectOptions ?? []
        let values = options.map(\.value)
        #expect(values.contains("Event"))
        #expect(values.contains("Meeting"))
        #expect(values.contains("Appointment"))
    }

    // MARK: - Test 3: round-trip preserves the new shape

    /// Encodes a migrated schema then decodes again — shape must be stable (no
    /// re-migration from legacy path on second decode, IDs preserved).
    @Test("round-trip encode → decode preserves PropertyDefinition shape and IDs")
    func roundTripPreservesNewShape() throws {
        let original = AgendaEventSchema.defaultSeed()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(AgendaEventSchema.self, from: data)

        #expect(decoded.properties.count == original.properties.count)
        for (orig, rt) in zip(original.properties, decoded.properties) {
            #expect(rt.id == orig.id)
            #expect(rt.name == orig.name)
            #expect(rt.type == orig.type)
        }
    }
}
