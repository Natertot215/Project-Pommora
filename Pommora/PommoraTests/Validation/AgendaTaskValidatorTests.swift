import Foundation
import Testing

@testable import Pommora

@Suite("AgendaTaskValidator")
struct AgendaTaskValidatorTests {

    /// A schema that mimics a legacy sidecar still carrying a `_type` Select
    /// property. Used for tests that exercise the conditional `_type` branch.
    private static func legacySchema() -> AgendaTaskSchema {
        let typeProp = PropertyDefinition(
            id: "_type",
            name: "Type",
            type: .select,
            selectOptions: [PropertyDefinition.SelectOption(value: "Task", label: "Task")]
        )
        var schema = AgendaTaskSchema.defaultSeed()
        schema.properties.append(typeProp)
        return schema
    }

    @Test("due-only task passes")
    func dueOnlyTask() throws {
        try AgendaTaskValidator.validate(
            title: "Buy",
            dueAt: Date(timeIntervalSince1970: 1000),
            dueAllDay: false,
            properties: ["type": .select("Task")],
            schema: Self.legacySchema()
        )
    }

    @Test("undated task passes")
    func undatedTask() throws {
        try AgendaTaskValidator.validate(
            title: "Someday",
            dueAt: nil,
            dueAllDay: false,
            properties: ["type": .select("Task")],
            schema: Self.legacySchema()
        )
    }

    @Test("empty title throws emptyTitle")
    func emptyTitle() {
        #expect(throws: AgendaTaskValidator.ValidationError.emptyTitle) {
            try AgendaTaskValidator.validate(
                title: "   ",
                dueAt: nil,
                dueAllDay: false,
                properties: ["type": .select("Task")],
                schema: AgendaTaskSchema.defaultSeed()
            )
        }
    }

    @Test("invalid title characters throws invalidTitleCharacters")
    func invalidTitleCharacters() {
        #expect(throws: AgendaTaskValidator.ValidationError.invalidTitleCharacters) {
            try AgendaTaskValidator.validate(
                title: "Bad/Name",
                dueAt: nil,
                dueAllDay: false,
                properties: ["type": .select("Task")],
                schema: AgendaTaskSchema.defaultSeed()
            )
        }
    }

    @Test("due_all_day without due_at throws dueAllDayWithoutDue")
    func dueAllDayWithoutDue() {
        #expect(throws: AgendaTaskValidator.ValidationError.dueAllDayWithoutDue) {
            try AgendaTaskValidator.validate(
                title: "X",
                dueAt: nil,
                dueAllDay: true,
                properties: ["type": .select("Task")],
                schema: AgendaTaskSchema.defaultSeed()
            )
        }
    }

    @Test("missing _type value throws missingTypeProperty on legacy schemas")
    func missingType() {
        #expect(throws: AgendaTaskValidator.ValidationError.missingTypeProperty) {
            try AgendaTaskValidator.validate(
                title: "X",
                dueAt: nil,
                dueAllDay: false,
                properties: [:],
                schema: Self.legacySchema()
            )
        }
    }

    @Test("_type value not in schema options throws unknownTypeValue on legacy schemas")
    func unknownTypeValue() {
        #expect(throws: AgendaTaskValidator.ValidationError.unknownTypeValue("Madeup")) {
            try AgendaTaskValidator.validate(
                title: "X",
                dueAt: nil,
                dueAllDay: false,
                properties: ["type": .select("Madeup")],
                schema: Self.legacySchema()
            )
        }
    }
}
