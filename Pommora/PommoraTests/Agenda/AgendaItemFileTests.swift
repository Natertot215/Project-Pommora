import Foundation
import Testing

@testable import Pommora

@Suite("AgendaItemFile")
struct AgendaItemFileTests {

    @Test("AgendaItem round-trips event-shaped item")
    func eventShapedRoundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Team standup.agenda.json")

        let original = AgendaItem(
            id: "01HAGENDA",
            title: "Team standup",
            icon: "person.3",
            startAt: Date(timeIntervalSince1970: 1716480000),
            endAt: Date(timeIntervalSince1970: 1716481800),
            allDay: false,
            dueAt: nil, dueFloating: false, dueAllDay: false,
            completed: false, completedAt: nil,
            location: "Conference room A",
            recurrence: nil,
            alarmOffsets: [-900],  // 15 min before
            alarmAbsolute: [],
            syncTarget: nil, calendarID: nil, eventkitUUID: nil,
            description: "Daily standup",
            tier1: [], tier2: ["01HTOPIC-WORK"], tier3: [],
            createdAt: Date(timeIntervalSince1970: 1716000000),
            modifiedAt: Date(timeIntervalSince1970: 1716480000),
            properties: ["type": .select("Event")]
        )
        try original.save(to: url)

        let loaded = try AgendaItem.load(from: url)
        #expect(loaded.id == "01HAGENDA")
        #expect(loaded.title == "Team standup")
        #expect(loaded.startAt != nil)
        #expect(loaded.endAt != nil)
        #expect(loaded.dueAt == nil)
        #expect(loaded.location == "Conference room A")
        #expect(loaded.alarmOffsets == [-900])
    }

    @Test("AgendaItem round-trips reminder-shaped item")
    func reminderShapedRoundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Buy groceries.agenda.json")

        let original = AgendaItem(
            id: "01HAGTASK",
            title: "Buy groceries",
            icon: "checkmark.circle",
            startAt: nil, endAt: nil, allDay: false,
            dueAt: Date(timeIntervalSince1970: 1716480000),
            dueFloating: true, dueAllDay: true,
            completed: false, completedAt: nil,
            location: nil, recurrence: nil,
            alarmOffsets: [], alarmAbsolute: [],
            syncTarget: nil, calendarID: nil, eventkitUUID: nil,
            description: "",
            tier1: [], tier2: [], tier3: [],
            createdAt: Date(), modifiedAt: Date(),
            properties: ["type": .select("Task")]
        )
        try original.save(to: url)

        let loaded = try AgendaItem.load(from: url)
        #expect(loaded.dueAt != nil)
        #expect(loaded.dueFloating == true)
        #expect(loaded.dueAllDay == true)
        #expect(loaded.startAt == nil)
    }

    @Test("Snake_case keys on disk")
    func snakeCase() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("X.agenda.json")
        // Populate the optional fields under test so encodeIfPresent emits their keys.
        try AgendaItem(
            id: "01H", title: "X", icon: nil,
            startAt: Date(timeIntervalSince1970: 1716480000),
            endAt: nil, allDay: false,
            dueAt: Date(timeIntervalSince1970: 1716480000),
            dueFloating: false, dueAllDay: false,
            completed: false, completedAt: nil,
            location: nil, recurrence: nil,
            alarmOffsets: [], alarmAbsolute: [],
            syncTarget: .calendar, calendarID: nil, eventkitUUID: "EK-UUID-1",
            description: "",
            tier1: [], tier2: [], tier3: [],
            createdAt: Date(), modifiedAt: Date(),
            properties: [:]
        ).save(to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("\"start_at\""))
        #expect(raw.contains("\"due_at\""))
        #expect(raw.contains("\"due_floating\""))
        #expect(raw.contains("\"alarm_offsets\""))
        #expect(raw.contains("\"sync_target\""))
        #expect(raw.contains("\"eventkit_uuid\""))
    }
}
