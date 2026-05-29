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
        relationTarget: PropertyDefinition.RelationTarget? = nil,
        dualProperty: PropertyDefinition.DualPropertyConfig? = nil
    ) -> PropertyDefinition {
        PropertyDefinition(
            id: id,
            name: name,
            type: type,
            selectOptions: selectOptions,
            relationTarget: relationTarget,
            dualProperty: dualProperty
        )
    }

    // MARK: - Rule 1: emptyName

    @Test func rejectsEmptyName() {
        #expect(throws: PropertyDefinitionValidator.ValidationError.emptyName) {
            try PropertyDefinitionValidator.validate(makeDef(name: ""), in: [])
        }
    }

    // MARK: - Rule 2: whitespaceOnlyName (same error as emptyName after trim)

    @Test func rejectsWhitespaceOnlyName() {
        #expect(throws: PropertyDefinitionValidator.ValidationError.emptyName) {
            try PropertyDefinitionValidator.validate(makeDef(name: "   "), in: [])
        }
    }

    // MARK: - Rule 3: reservedID

    @Test func rejectsReservedID() {
        #expect(throws: PropertyDefinitionValidator.ValidationError.reservedID) {
            try PropertyDefinitionValidator.validate(makeDef(id: "_status"), in: [])
        }
    }

    // MARK: - Rule 4: duplicateID

    @Test func rejectsDuplicateID() {
        let existing = [makeDef(id: "prop_abc", name: "Existing")]
        #expect(throws: PropertyDefinitionValidator.ValidationError.duplicateID) {
            try PropertyDefinitionValidator.validate(makeDef(id: "prop_abc", name: "New"), in: existing)
        }
    }

    // MARK: - Rule 5: caseInsensitiveDuplicateName

    @Test func rejectsCaseInsensitiveDuplicateName() {
        let existing = [makeDef(id: "prop_xyz", name: "Priority")]
        #expect(throws: PropertyDefinitionValidator.ValidationError.duplicateName) {
            try PropertyDefinitionValidator.validate(makeDef(id: "prop_abc", name: "PRIORITY"), in: existing)
        }
    }

    // MARK: - Rule 6: dualRelationOnContextTier

    @Test func rejectsDualRelationOnContextTier() {
        let dual = PropertyDefinition.DualPropertyConfig(
            syncedPropertyID: "prop_rev",
            syncedPropertyDefinedOnTypeID: "type_123"
        )
        let def = makeDef(
            type: .relation,
            relationTarget: .contextTier(3),
            dualProperty: dual
        )
        #expect(throws: PropertyDefinitionValidator.ValidationError.dualRelationOnContextTier) {
            try PropertyDefinitionValidator.validate(def, in: [])
        }
    }

    // MARK: - Rule 7: selectWithZeroOptions

    @Test func rejectsSelectWithZeroOptions() {
        let def = makeDef(type: .select, selectOptions: [])
        #expect(throws: PropertyDefinitionValidator.ValidationError.selectMissingOptions) {
            try PropertyDefinitionValidator.validate(def, in: [])
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
            try PropertyDefinitionValidator.validate(def, in: [])
        }
    }
}
