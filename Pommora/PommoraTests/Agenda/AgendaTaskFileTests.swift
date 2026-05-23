import Foundation
import Testing

@testable import Pommora

@Suite("AgendaTaskFile")
struct AgendaTaskFileTests {

    @Test("AgendaTask round-trips a reminder-shaped task")
    func reminderShapedRoundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Buy groceries.task.json")

        let original = AgendaTask(
            id: "01HAGTASK",
            title: "Buy groceries",
            icon: "checkmark.circle",
            description: "",
            dueAt: Date(timeIntervalSince1970: 1716480000),
            dueFloating: true,
            dueAllDay: true,
            startAt: nil,
            completed: false,
            completedAt: nil,
            priority: 5,
            recurrence: nil,
            alarmOffsets: [],
            calendarID: nil,
            eventkitUUID: nil,
            tier1: [],
            tier2: [],
            tier3: [],
            createdAt: Date(timeIntervalSince1970: 1716000000),
            modifiedAt: Date(timeIntervalSince1970: 1716480000),
            properties: ["type": .select("Task")]
        )
        try original.save(to: url)

        let loaded = try AgendaTask.load(from: url)
        #expect(loaded.id == "01HAGTASK")
        #expect(loaded.title == "Buy groceries")
        #expect(loaded.dueAt != nil)
        #expect(loaded.dueFloating == true)
        #expect(loaded.dueAllDay == true)
        #expect(loaded.startAt == nil)
        #expect(loaded.priority == 5)
        #expect(loaded.completed == false)
    }

    @Test("AgendaTask round-trips a completed task")
    func completedTaskRoundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Done.task.json")

        let completedAt = Date(timeIntervalSince1970: 1716500000)
        let original = AgendaTask(
            id: "01HDONE",
            title: "Done",
            icon: nil,
            description: "Completed item",
            dueAt: nil,
            dueFloating: false,
            dueAllDay: false,
            startAt: nil,
            completed: true,
            completedAt: completedAt,
            priority: 0,
            recurrence: nil,
            alarmOffsets: [-900],
            calendarID: nil,
            eventkitUUID: nil,
            tier1: [],
            tier2: ["01HTOPIC-WORK"],
            tier3: [],
            createdAt: Date(),
            modifiedAt: Date(),
            properties: ["type": .select("Task")]
        )
        try original.save(to: url)

        let loaded = try AgendaTask.load(from: url)
        #expect(loaded.completed == true)
        #expect(loaded.completedAt == completedAt)
        #expect(loaded.alarmOffsets == [-900])
        #expect(loaded.tier2 == ["01HTOPIC-WORK"])
    }

    @Test("Snake_case keys on disk")
    func snakeCase() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("X.task.json")
        try AgendaTask(
            id: "01H",
            title: "X",
            icon: nil,
            description: "",
            dueAt: Date(timeIntervalSince1970: 1716480000),
            dueFloating: true,
            dueAllDay: false,
            startAt: Date(timeIntervalSince1970: 1716000000),
            completed: false,
            completedAt: nil,
            priority: 0,
            recurrence: nil,
            alarmOffsets: [],
            calendarID: nil,
            eventkitUUID: "EK-UUID-1",
            tier1: [],
            tier2: [],
            tier3: [],
            createdAt: Date(),
            modifiedAt: Date(),
            properties: [:]
        ).save(to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("\"due_at\""))
        #expect(raw.contains("\"due_floating\""))
        #expect(raw.contains("\"due_all_day\""))
        #expect(raw.contains("\"start_at\""))
        #expect(raw.contains("\"alarm_offsets\""))
        #expect(raw.contains("\"eventkit_uuid\""))
        #expect(raw.contains("\"created_at\""))
        #expect(raw.contains("\"modified_at\""))
    }

    @Test("title derives from .task.json filename")
    func titleFromFilename() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("My Task.task.json")
        try AgendaTask(
            id: "01H",
            title: "",  // empty on save; load should rederive
            icon: nil,
            description: "",
            dueAt: nil,
            dueFloating: false,
            dueAllDay: false,
            startAt: nil,
            completed: false,
            completedAt: nil,
            priority: 0,
            recurrence: nil,
            alarmOffsets: [],
            calendarID: nil,
            eventkitUUID: nil,
            tier1: [],
            tier2: [],
            tier3: [],
            createdAt: Date(),
            modifiedAt: Date(),
            properties: [:]
        ).save(to: url)
        let loaded = try AgendaTask.load(from: url)
        #expect(loaded.title == "My Task")
    }
}
