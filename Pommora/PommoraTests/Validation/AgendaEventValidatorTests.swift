import Foundation
import Testing

@testable import Pommora

@Suite("AgendaEventValidator")
struct AgendaEventValidatorTests {

    /// A schema that mimics a legacy sidecar still carrying a `_type` Select
    /// property. Used for tests that exercise the conditional `_type` branch.
    private static func legacySchema() -> AgendaEventSchema {
        let typeProp = PropertyDefinition(
            id: "_type",
            name: "Type",
            type: .select,
            selectOptions: [PropertyDefinition.SelectOption(value: "Event", label: "Event")]
        )
        var schema = AgendaEventSchema.defaultSeed()
        schema.properties.append(typeProp)
        return schema
    }

    @Test("event with start <= end passes")
    func validEvent() throws {
        try AgendaEventValidator.validate(
            title: "Standup",
            startAt: Date(timeIntervalSince1970: 100),
            endAt: Date(timeIntervalSince1970: 200),
            properties: ["type": .select("Event")],
            schema: Self.legacySchema()
        )
    }

    @Test("zero-duration event (start == end) passes")
    func zeroDurationEvent() throws {
        let t = Date(timeIntervalSince1970: 100)
        try AgendaEventValidator.validate(
            title: "Instant",
            startAt: t,
            endAt: t,
            properties: ["type": .select("Event")],
            schema: Self.legacySchema()
        )
    }

    @Test("empty title throws emptyTitle")
    func emptyTitle() {
        #expect(throws: AgendaEventValidator.ValidationError.emptyTitle) {
            try AgendaEventValidator.validate(
                title: "  ",
                startAt: Date(timeIntervalSince1970: 100),
                endAt: Date(timeIntervalSince1970: 200),
                properties: ["type": .select("Event")],
                schema: AgendaEventSchema.defaultSeed()
            )
        }
    }

    @Test("invalid title characters throws invalidTitleCharacters")
    func invalidTitleCharacters() {
        #expect(throws: AgendaEventValidator.ValidationError.invalidTitleCharacters) {
            try AgendaEventValidator.validate(
                title: "Bad:Name",
                startAt: Date(timeIntervalSince1970: 100),
                endAt: Date(timeIntervalSince1970: 200),
                properties: ["type": .select("Event")],
                schema: AgendaEventSchema.defaultSeed()
            )
        }
    }

    @Test("end_at before start_at throws endBeforeStart")
    func endBeforeStart() {
        #expect(throws: AgendaEventValidator.ValidationError.endBeforeStart) {
            try AgendaEventValidator.validate(
                title: "X",
                startAt: Date(timeIntervalSince1970: 200),
                endAt: Date(timeIntervalSince1970: 100),
                properties: ["type": .select("Event")],
                schema: AgendaEventSchema.defaultSeed()
            )
        }
    }

    @Test("missing _type value throws missingTypeProperty on legacy schemas")
    func missingType() {
        #expect(throws: AgendaEventValidator.ValidationError.missingTypeProperty) {
            try AgendaEventValidator.validate(
                title: "X",
                startAt: Date(timeIntervalSince1970: 100),
                endAt: Date(timeIntervalSince1970: 200),
                properties: [:],
                schema: Self.legacySchema()
            )
        }
    }

    @Test("_type value not in schema options throws unknownTypeValue on legacy schemas")
    func unknownTypeValue() {
        #expect(throws: AgendaEventValidator.ValidationError.unknownTypeValue("Madeup")) {
            try AgendaEventValidator.validate(
                title: "X",
                startAt: Date(timeIntervalSince1970: 100),
                endAt: Date(timeIntervalSince1970: 200),
                properties: ["type": .select("Madeup")],
                schema: Self.legacySchema()
            )
        }
    }
}
