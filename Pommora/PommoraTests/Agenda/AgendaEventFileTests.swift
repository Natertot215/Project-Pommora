import Foundation
import Testing

@testable import Pommora

@Suite("AgendaEventFile")
struct AgendaEventFileTests {

    @Test("AgendaEvent round-trips a meeting-shaped event")
    func meetingShapedRoundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Team standup.event.json")

        let original = AgendaEvent(
            id: "01HAGEVENT",
            title: "Team standup",
            icon: "person.3",
            description: "Daily standup",
            startAt: Date(timeIntervalSince1970: 1716480000),
            endAt: Date(timeIntervalSince1970: 1716481800),
            allDay: false,
            location: "Conference room A",
            recurrence: nil,
            alarmOffsets: [-900],  // 15 min before
            alarmAbsolute: [],
            calendarID: nil,
            eventkitUUID: nil,
            tier1: [],
            tier2: ["01HTOPIC-WORK"],
            tier3: [],
            createdAt: Date(timeIntervalSince1970: 1716000000),
            modifiedAt: Date(timeIntervalSince1970: 1716480000),
            properties: ["type": .select("Event")]
        )
        try original.save(to: url)

        let loaded = try AgendaEvent.load(from: url)
        #expect(loaded.id == "01HAGEVENT")
        #expect(loaded.title == "Team standup")
        #expect(loaded.startAt == Date(timeIntervalSince1970: 1716480000))
        #expect(loaded.endAt == Date(timeIntervalSince1970: 1716481800))
        #expect(loaded.location == "Conference room A")
        #expect(loaded.alarmOffsets == [-900])
    }

    @Test("AgendaEvent round-trips an all-day event")
    func allDayEventRoundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Birthday.event.json")

        let original = AgendaEvent(
            id: "01HBDAY",
            title: "Birthday",
            icon: "gift",
            description: "",
            startAt: Date(timeIntervalSince1970: 1716480000),
            endAt: Date(timeIntervalSince1970: 1716566400),
            allDay: true,
            location: nil,
            recurrence: nil,
            alarmOffsets: [],
            alarmAbsolute: [Date(timeIntervalSince1970: 1716470000)],
            calendarID: nil,
            eventkitUUID: nil,
            tier1: [],
            tier2: [],
            tier3: [],
            createdAt: Date(),
            modifiedAt: Date(),
            properties: ["type": .select("Event")]
        )
        try original.save(to: url)

        let loaded = try AgendaEvent.load(from: url)
        #expect(loaded.allDay == true)
        #expect(loaded.location == nil)
        #expect(loaded.alarmAbsolute.count == 1)
    }

    @Test("Snake_case keys on disk")
    func snakeCase() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("X.event.json")
        try AgendaEvent(
            id: "01H",
            title: "X",
            icon: nil,
            description: "",
            startAt: Date(timeIntervalSince1970: 1716480000),
            endAt: Date(timeIntervalSince1970: 1716483600),
            allDay: false,
            location: "Office",
            recurrence: nil,
            alarmOffsets: [],
            alarmAbsolute: [Date(timeIntervalSince1970: 1716480000)],
            calendarID: nil,
            eventkitUUID: "EK-UUID-EVT",
            tier1: [],
            tier2: [],
            tier3: [],
            createdAt: Date(),
            modifiedAt: Date(),
            properties: [:]
        ).save(to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("\"start_at\""))
        #expect(raw.contains("\"end_at\""))
        #expect(raw.contains("\"all_day\""))
        #expect(raw.contains("\"alarm_offsets\""))
        #expect(raw.contains("\"alarm_absolute\""))
        #expect(raw.contains("\"eventkit_uuid\""))
        #expect(raw.contains("\"created_at\""))
        #expect(raw.contains("\"modified_at\""))
    }

    @Test("title derives from .event.json filename")
    func titleFromFilename() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("My Event.event.json")
        try AgendaEvent(
            id: "01H",
            title: "",  // empty on save; load should rederive
            icon: nil,
            description: "",
            startAt: Date(timeIntervalSince1970: 1716480000),
            endAt: Date(timeIntervalSince1970: 1716481800),
            allDay: false,
            location: nil,
            recurrence: nil,
            alarmOffsets: [],
            alarmAbsolute: [],
            calendarID: nil,
            eventkitUUID: nil,
            tier1: [],
            tier2: [],
            tier3: [],
            createdAt: Date(),
            modifiedAt: Date(),
            properties: [:]
        ).save(to: url)
        let loaded = try AgendaEvent.load(from: url)
        #expect(loaded.title == "My Event")
    }
}
