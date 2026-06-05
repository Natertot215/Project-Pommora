import Foundation
import Testing

@testable import Pommora

@Suite("PropertyDefinitionValidator")
struct PropertyDefinitionValidatorTests {

    // MARK: - Helpers

    private func makeDef(
        id: String = "prop_abc",
        name: String = "My Property",
        type: PropertyType = .number,
        selectOptions: [PropertyDefinition.SelectOption]? = nil,
        relationTarget: PropertyDefinition.RelationTarget? = nil
    ) -> PropertyDefinition {
        PropertyDefinition(
            id: id,
            name: name,
            type: type,
            selectOptions: selectOptions,
            relationTarget: relationTarget
        )
    }

    // MARK: - Rule 1: emptyName

    @Test func rejectsEmptyName() {
        #expect(throws: PropertyDefinitionValidator.ValidationError.emptyName) {
            try PropertyDefinitionValidator.validate(makeDef(name: ""), in: [], nexus: .empty)
        }
    }

    // MARK: - Rule 2: whitespaceOnlyName (same error as emptyName after trim)

    @Test func rejectsWhitespaceOnlyName() {
        #expect(throws: PropertyDefinitionValidator.ValidationError.emptyName) {
            try PropertyDefinitionValidator.validate(makeDef(name: "   "), in: [], nexus: .empty)
        }
    }

    // MARK: - Rule 3: reservedID

    @Test func rejectsReservedID() {
        #expect(throws: PropertyDefinitionValidator.ValidationError.reservedID) {
            try PropertyDefinitionValidator.validate(makeDef(id: "_status"), in: [], nexus: .empty)
        }
    }

    // MARK: - Rule 4: duplicateID

    @Test func rejectsDuplicateID() {
        let existing = [makeDef(id: "prop_abc", name: "Existing")]
        #expect(throws: PropertyDefinitionValidator.ValidationError.duplicateID) {
            try PropertyDefinitionValidator.validate(
                makeDef(id: "prop_abc", name: "New"), in: existing, nexus: .empty)
        }
    }

    // MARK: - Rule 5: caseInsensitiveDuplicateName

    @Test func rejectsCaseInsensitiveDuplicateName() {
        let existing = [makeDef(id: "prop_xyz", name: "Priority")]
        #expect(throws: PropertyDefinitionValidator.ValidationError.duplicateName) {
            try PropertyDefinitionValidator.validate(
                makeDef(id: "prop_abc", name: "PRIORITY"), in: existing, nexus: .empty)
        }
    }

    // MARK: - Relation: missing target

    @Test func rejectsRelationWithNoTarget() {
        let def = makeDef(type: .relation, relationTarget: nil)
        #expect(throws: PropertyDefinitionValidator.ValidationError.relationMissingTarget) {
            try PropertyDefinitionValidator.validate(def, in: [], nexus: .empty)
        }
    }

    // MARK: - Relation: unresolvable PageType target

    @Test func rejectsRelationWithUnresolvablePageTypeTarget() {
        let def = makeDef(type: .relation, relationTarget: .pageType("does_not_exist"))
        #expect(
            throws: PropertyDefinitionValidator.ValidationError.relationTargetNotResolvable(
                typeID: "does_not_exist")
        ) {
            try PropertyDefinitionValidator.validate(def, in: [], nexus: .empty)
        }
    }

    // MARK: - Relation: unresolvable ItemType target

    @Test func rejectsRelationWithUnresolvableItemTypeTarget() {
        let def = makeDef(type: .relation, relationTarget: .itemType("missing_item_type"))
        #expect(
            throws: PropertyDefinitionValidator.ValidationError.relationTargetNotResolvable(
                typeID: "missing_item_type")
        ) {
            try PropertyDefinitionValidator.validate(def, in: [], nexus: .empty)
        }
    }

    // MARK: - Relation: legacy Collection targets rejected at save time

    @Test func rejectsRelationWithLegacyCollectionTarget() {
        let def = makeDef(type: .relation, relationTarget: .pageCollection("legacy_collection"))
        #expect(
            throws: PropertyDefinitionValidator.ValidationError.relationTargetNotResolvable(
                typeID: "legacy_collection")
        ) {
            try PropertyDefinitionValidator.validate(def, in: [], nexus: .empty)
        }
    }

    // MARK: - Relation: Agenda singleton targets accepted without catalog lookup

    @Test func acceptsRelationWithAgendaTasksTarget() {
        let def = makeDef(type: .relation, relationTarget: .agendaTasks)
        #expect(throws: Never.self) {
            try PropertyDefinitionValidator.validate(def, in: [], nexus: .empty)
        }
    }

    @Test func acceptsRelationWithAgendaEventsTarget() {
        let def = makeDef(type: .relation, relationTarget: .agendaEvents)
        #expect(throws: Never.self) {
            try PropertyDefinitionValidator.validate(def, in: [], nexus: .empty)
        }
    }

    // MARK: - Relation: contextTier accepted without catalog lookup (Rule 6 retired)

    @Test func acceptsRelationWithContextTierTarget() {
        let def = makeDef(type: .relation, relationTarget: .contextTier(3))
        #expect(throws: Never.self) {
            try PropertyDefinitionValidator.validate(def, in: [], nexus: .empty)
        }
    }

    // MARK: - Rule 7: selectWithZeroOptions

    @Test func rejectsSelectWithZeroOptions() {
        let def = makeDef(type: .select, selectOptions: [])
        #expect(throws: PropertyDefinitionValidator.ValidationError.selectMissingOptions) {
            try PropertyDefinitionValidator.validate(def, in: [], nexus: .empty)
        }
    }

    // MARK: - Rule 8: duplicateOptionValuesInSelect

    @Test func rejectsDuplicateOptionValuesInSelect() {
        let options = [
            PropertyDefinition.SelectOption(value: "a", label: "A"),
            PropertyDefinition.SelectOption(value: "a", label: "A Again"),
        ]
        let def = makeDef(type: .select, selectOptions: options)
        #expect(throws: PropertyDefinitionValidator.ValidationError.duplicateSelectOptionValue) {
            try PropertyDefinitionValidator.validate(def, in: [], nexus: .empty)
        }
    }
}
