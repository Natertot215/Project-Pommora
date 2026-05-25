import Foundation
import Testing
@testable import Pommora

@Suite("PropertyDefinition") struct PropertyDefinitionTests {
    // MARK: - Stored id field (Phase A.5)

    @Test func storesIDIndependentlyOfName() throws {
        var def = PropertyDefinition(id: "prop_01HABC", name: "Status", type: .status)
        #expect(def.id == "prop_01HABC")
        def.name = "Tags"  // rename is schema-only; id never changes
        #expect(def.id == "prop_01HABC")
    }

    @Test func encodesIDFieldInJSON() throws {
        let def = PropertyDefinition(id: "prop_01HABC", name: "Status", type: .status)
        let data = try JSONEncoder().encode(def)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""id":"prop_01HABC""#))
        #expect(s.contains(#""name":"Status""#))
        #expect(s.contains(#""type":"status""#))
    }

    @Test func decodesLegacyDefinitionWithoutIDField() throws {
        // Pre-v0.3.0 schemas have no `id` field. Decode synthesises "" — the
        // adoption-scan migration backfills with a freshly-minted ULID.
        let json = #"{"name": "Status", "type": "status"}"#.data(using: .utf8)!
        let def = try JSONDecoder().decode(PropertyDefinition.self, from: json)
        #expect(def.id.isEmpty)
        #expect(def.name == "Status")
        #expect(def.type == .status)
    }

    @Test func roundTripWithAllConfigFields() throws {
        let def = PropertyDefinition(
            id: "prop_01HALL",
            name: "Everything",
            type: .relation,
            icon: "doc.text.magnifyingglass",
            numberFormat: nil,
            dateIncludesTime: nil,
            selectOptions: nil,
            statusGroups: nil,
            relationScope: .pageType("01HTARGET"),
            allowsMultiple: true,
            dualProperty: PropertyDefinition.DualPropertyConfig(
                syncedPropertyID: "prop_01HREVERSE",
                syncedPropertyDefinedOnTypeID: "01HTARGET"
            ),
            accept: nil
        )
        let data = try JSONEncoder().encode(def)
        let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: data)
        #expect(decoded == def)
    }

    @Test func optionalConfigFieldsOmittedWhenNil() throws {
        let def = PropertyDefinition(id: "prop_01H", name: "Plain", type: .number)
        let data = try JSONEncoder().encode(def)
        let s = String(data: data, encoding: .utf8)!
        // No null-valued optionals in the JSON
        #expect(!s.contains("\"icon\""))
        #expect(!s.contains("\"relation_scope\""))
        #expect(!s.contains("\"dual_property\""))
        #expect(!s.contains("\"accept\""))
    }

    @Test func acceptListRoundTrip() throws {
        let def = PropertyDefinition(
            id: "prop_01HFILE", name: "Attachments", type: .file,
            accept: ["application/pdf", "image/*"]
        )
        let data = try JSONEncoder().encode(def)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""accept":["application\/pdf","image\/*"]"#))
        let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: data)
        #expect(decoded.accept == ["application/pdf", "image/*"])
    }

    // MARK: - StatusGroup / StatusOption / StatusGroupID (Phase A.6)

    @Test func statusGroupIDFixedThreeValues() {
        #expect(PropertyDefinition.StatusGroupID.allCases == [.upcoming, .inProgress, .done])
    }

    @Test func statusGroupIDEncodesSnakeCase() throws {
        let id = PropertyDefinition.StatusGroupID.inProgress
        let data = try JSONEncoder().encode(id)
        #expect(String(data: data, encoding: .utf8) == #""in_progress""#)
    }

    @Test func defaultSeedStatusGroups() {
        let groups = PropertyDefinition.StatusGroup.defaultSeed()
        #expect(groups.count == 3)
        #expect(groups[0].id == .upcoming)
        #expect(groups[0].label == "Upcoming")
        #expect(groups[0].color == .gray)
        #expect(groups[0].options.count == 1)
        #expect(groups[0].options[0].value == "not_started")
        #expect(groups[0].options[0].groupID == .upcoming)
        #expect(groups[1].id == .inProgress)
        #expect(groups[1].options[0].value == "in_progress")
        #expect(groups[2].id == .done)
        #expect(groups[2].options[0].value == "done")
    }

    @Test func statusGroupRoundTrip() throws {
        let groups = PropertyDefinition.StatusGroup.defaultSeed()
        let data = try JSONEncoder().encode(groups)
        let decoded = try JSONDecoder().decode([PropertyDefinition.StatusGroup].self, from: data)
        #expect(decoded == groups)
    }

    @Test func statusOptionSnakeCaseGroupID() throws {
        let option = PropertyDefinition.StatusOption(
            value: "blocked", label: "Blocked", color: .red, groupID: .upcoming
        )
        let data = try JSONEncoder().encode(option)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""group_id":"upcoming""#))
        #expect(s.contains(#""value":"blocked""#))
    }

    @Test func dualPropertyConfigSnakeCase() throws {
        let dual = PropertyDefinition.DualPropertyConfig(
            syncedPropertyID: "prop_01HCITED",
            syncedPropertyDefinedOnTypeID: "01HMATERIAL"
        )
        let data = try JSONEncoder().encode(dual)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""synced_property_id":"prop_01HCITED""#))
        #expect(s.contains(#""synced_property_defined_on_type_id":"01HMATERIAL""#))
    }

    @Test func dualPropertyConfigRoundTrip() throws {
        let dual = PropertyDefinition.DualPropertyConfig(
            syncedPropertyID: "prop_a", syncedPropertyDefinedOnTypeID: "01HT"
        )
        let data = try JSONEncoder().encode(dual)
        let decoded = try JSONDecoder().decode(PropertyDefinition.DualPropertyConfig.self, from: data)
        #expect(decoded == dual)
    }

    @Test func statusPropertyDefinitionRoundTripWithGroups() throws {
        let def = PropertyDefinition(
            id: "_status", name: "Status", type: .status,
            statusGroups: PropertyDefinition.StatusGroup.defaultSeed()
        )
        let data = try JSONEncoder().encode(def)
        let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: data)
        #expect(decoded == def)
        #expect(decoded.statusGroups?.count == 3)
    }
}
