import Foundation
import Testing
@testable import Pommora

@Suite("AgendaValidator")
struct AgendaValidatorTests {

    @Test("event-shaped (start+end) passes")
    func eventShape() throws {
        try AgendaValidator.validate(
            title: "Standup",
            startAt: Date(timeIntervalSince1970: 100),
            endAt: Date(timeIntervalSince1970: 200),
            allDay: false,
            dueAt: nil, dueAllDay: false,
            properties: ["type": .select("Event")],
            schema: AgendaSchema.defaultSeed()
        )
    }

    @Test("reminder-shaped (due_at only) passes")
    func reminderShape() throws {
        try AgendaValidator.validate(
            title: "Buy", startAt: nil, endAt: nil, allDay: false,
            dueAt: Date(timeIntervalSince1970: 1000), dueAllDay: false,
            properties: ["type": .select("Task")],
            schema: AgendaSchema.defaultSeed()
        )
    }

    @Test("start_at without end_at throws missingEndAt")
    func startWithoutEnd() {
        #expect(throws: AgendaValidator.ValidationError.missingEndAt) {
            try AgendaValidator.validate(
                title: "X",
                startAt: Date(timeIntervalSince1970: 100),
                endAt: nil,
                allDay: false,
                dueAt: nil, dueAllDay: false,
                properties: ["type": .select("Event")],
                schema: AgendaSchema.defaultSeed()
            )
        }
    }

    @Test("end_at before start_at throws endBeforeStart")
    func endBeforeStart() {
        #expect(throws: AgendaValidator.ValidationError.endBeforeStart) {
            try AgendaValidator.validate(
                title: "X",
                startAt: Date(timeIntervalSince1970: 200),
                endAt: Date(timeIntervalSince1970: 100),
                allDay: false,
                dueAt: nil, dueAllDay: false,
                properties: ["type": .select("Event")],
                schema: AgendaSchema.defaultSeed()
            )
        }
    }

    @Test("all_day without start_at throws allDayWithoutStart")
    func allDayWithoutStart() {
        #expect(throws: AgendaValidator.ValidationError.allDayWithoutStart) {
            try AgendaValidator.validate(
                title: "X", startAt: nil, endAt: nil, allDay: true,
                dueAt: nil, dueAllDay: false,
                properties: ["type": .select("Task")],
                schema: AgendaSchema.defaultSeed()
            )
        }
    }

    @Test("due_all_day without due_at throws dueAllDayWithoutDue")
    func dueAllDayWithoutDue() {
        #expect(throws: AgendaValidator.ValidationError.dueAllDayWithoutDue) {
            try AgendaValidator.validate(
                title: "X", startAt: nil, endAt: nil, allDay: false,
                dueAt: nil, dueAllDay: true,
                properties: ["type": .select("Task")],
                schema: AgendaSchema.defaultSeed()
            )
        }
    }

    @Test("missing type property throws missingTypeProperty")
    func missingType() {
        #expect(throws: AgendaValidator.ValidationError.missingTypeProperty) {
            try AgendaValidator.validate(
                title: "X", startAt: nil, endAt: nil, allDay: false,
                dueAt: nil, dueAllDay: false,
                properties: [:],
                schema: AgendaSchema.defaultSeed()
            )
        }
    }

    @Test("type value not in schema options throws unknownTypeValue")
    func unknownTypeValue() {
        #expect(throws: AgendaValidator.ValidationError.unknownTypeValue("Madeup")) {
            try AgendaValidator.validate(
                title: "X", startAt: nil, endAt: nil, allDay: false,
                dueAt: nil, dueAllDay: false,
                properties: ["type": .select("Madeup")],
                schema: AgendaSchema.defaultSeed()
            )
        }
    }
}
