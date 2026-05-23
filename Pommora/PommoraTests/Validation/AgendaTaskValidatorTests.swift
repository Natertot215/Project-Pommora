import Foundation
import Testing

@testable import Pommora

@Suite("AgendaTaskValidator")
struct AgendaTaskValidatorTests {

    @Test("due-only task passes")
    func dueOnlyTask() throws {
        try AgendaTaskValidator.validate(
            title: "Buy",
            dueAt: Date(timeIntervalSince1970: 1000),
            dueAllDay: false,
            properties: ["type": .select("Task")],
            schema: AgendaTaskSchema.defaultSeed()
        )
    }

    @Test("undated task passes")
    func undatedTask() throws {
        try AgendaTaskValidator.validate(
            title: "Someday",
            dueAt: nil,
            dueAllDay: false,
            properties: ["type": .select("To-Do")],
            schema: AgendaTaskSchema.defaultSeed()
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

    @Test("missing type property throws missingTypeProperty")
    func missingType() {
        #expect(throws: AgendaTaskValidator.ValidationError.missingTypeProperty) {
            try AgendaTaskValidator.validate(
                title: "X",
                dueAt: nil,
                dueAllDay: false,
                properties: [:],
                schema: AgendaTaskSchema.defaultSeed()
            )
        }
    }

    @Test("type value not in schema options throws unknownTypeValue")
    func unknownTypeValue() {
        #expect(throws: AgendaTaskValidator.ValidationError.unknownTypeValue("Madeup")) {
            try AgendaTaskValidator.validate(
                title: "X",
                dueAt: nil,
                dueAllDay: false,
                properties: ["type": .select("Madeup")],
                schema: AgendaTaskSchema.defaultSeed()
            )
        }
    }
}
