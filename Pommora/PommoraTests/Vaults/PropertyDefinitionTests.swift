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
            relationTarget: .pageType("01HTARGET"),
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

    // MARK: - reverseName / reverseIcon (Phase 3)

    @Test func reverseFieldsRoundTrip() throws {
        let def = PropertyDefinition(
            id: "_tier1",
            name: "Branch",
            type: .relation,
            relationTarget: .contextTier(1),
            reverseName: "Books from this Branch",
            reverseIcon: "book"
        )
        let data = try JSONEncoder().encode(def)
        let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: data)
        #expect(decoded.reverseName == "Books from this Branch")
        #expect(decoded.reverseIcon == "book")
    }

    @Test func legacyDecodeWithoutReverseKeys() throws {
        // JSON that has no reverse_name / reverse_icon keys — both must decode to nil.
        let json = """
        {
            "id": "_tier1",
            "name": "Branch",
            "type": "relation",
            "relation_scope": {"kind": "context_tier", "tier": 1}
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: json)
        #expect(decoded.reverseName == nil)
        #expect(decoded.reverseIcon == nil)
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

    // MARK: - allows_multiple legacy tolerance (Relations Redesign)

    @Test func decoderToleratesLegacyAllowsMultipleField() throws {
        // Old on-disk JSON that still contains "allows_multiple": true must decode
        // without error; the unknown key is simply ignored.
        let json = """
        {
            "id": "prop_01HLEGACY",
            "name": "Related Items",
            "type": "relation",
            "relation_scope": {"kind": "item_type", "item_type_id": "t1"},
            "allows_multiple": true
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: json)
        #expect(decoded.id == "prop_01HLEGACY")
    }

    @Test func encoderDoesNotEmitAllowsMultiple() throws {
        // Encoding a relation PropertyDefinition must not include "allows_multiple"
        // in the output — the field no longer exists.
        let def = PropertyDefinition(
            id: "prop_01HREL",
            name: "Links",
            type: .relation,
            relationTarget: .itemType("t1")
        )
        let data = try JSONEncoder().encode(def)
        let json = String(data: data, encoding: .utf8)!
        #expect(!json.contains("allows_multiple"))
    }

    // MARK: - Phase 7: dual-key decode tolerance + encoder key

    @Test func decoderAcceptsBothRelationScopeAndRelationTargetKeys() throws {
        // JSON using the legacy "relation_scope" key
        let legacyJSON = """
        {
            "id": "prop_01HLEG",
            "name": "Legacy Rel",
            "type": "relation",
            "relation_scope": {"kind": "page_type", "page_type_id": "01HPTYPE"}
        }
        """.data(using: .utf8)!

        // JSON using the new "relation_target" key
        let newJSON = """
        {
            "id": "prop_01HNEW",
            "name": "New Rel",
            "type": "relation",
            "relation_target": {"kind": "page_type", "page_type_id": "01HPTYPE"}
        }
        """.data(using: .utf8)!

        let decodedLegacy = try JSONDecoder().decode(PropertyDefinition.self, from: legacyJSON)
        let decodedNew = try JSONDecoder().decode(PropertyDefinition.self, from: newJSON)

        #expect(decodedLegacy.relationTarget == .pageType("01HPTYPE"))
        #expect(decodedNew.relationTarget == .pageType("01HPTYPE"))
    }

    @Test func encoderEmitsRelationTargetKeyNotRelationScope() throws {
        let def = PropertyDefinition(
            id: "prop_01HENCODE",
            name: "My Relation",
            type: .relation,
            relationTarget: .pageType("01HPTYPE")
        )
        let data = try JSONEncoder().encode(def)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"relation_target\""))
        #expect(!json.contains("\"relation_scope\""))
    }
}
