import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("AgendaEventManager")
struct AgendaEventManagerTests {

    private func makeEvent(
        id: String = ULID.generate(),
        title: String,
        startAt: Date = Date(timeIntervalSince1970: 1716480000),
        endAt: Date = Date(timeIntervalSince1970: 1716483600),
        propertyType: String = "Event"
    ) -> AgendaEvent {
        AgendaEvent(
            id: id,
            title: title,
            icon: nil,
            description: "",
            startAt: startAt,
            endAt: endAt,
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
            properties: ["type": .select(propertyType)]
        )
    }

    @Test("loadAll seeds Events/_schema.json if missing")
    func seedsSchema() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()
        let schemaURL = NexusPaths.eventSchemaURL(in: nexus)
        #expect(FileManager.default.fileExists(atPath: schemaURL.path))
        let loaded = try AtomicJSON.decode(AgendaEventSchema.self, from: schemaURL)
        #expect(loaded.properties.contains { $0.name == "type" && $0.builtin })
    }

    @Test("createEvent writes .event.json with type=Event")
    func createEventCase() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        let event = makeEvent(title: "Team standup")
        try await manager.createEvent(event)
        let url = NexusPaths.eventFileURL(forTitle: "Team standup", in: nexus)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(manager.events.count == 1)
    }

    @Test("createEvent with invalid type throws")
    func invalidType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        let event = makeEvent(title: "X", propertyType: "Bogus")
        await #expect(throws: AgendaEventValidator.ValidationError.unknownTypeValue("Bogus")) {
            try await manager.createEvent(event)
        }
    }

    @Test("createEvent with end < start throws endBeforeStart")
    func endBeforeStart() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        let event = makeEvent(
            title: "Backwards",
            startAt: Date(timeIntervalSince1970: 2000),
            endAt: Date(timeIntervalSince1970: 1000)
        )
        await #expect(throws: AgendaEventValidator.ValidationError.endBeforeStart) {
            try await manager.createEvent(event)
        }
    }

    @Test("updateEvent refuses title changes — must use renameEvent first")
    func updateEventRefusesTitleChange() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        let id = ULID.generate()
        let event = makeEvent(id: id, title: "Original")
        try await manager.createEvent(event)

        var changed = event
        changed.title = "Renamed-without-rename"
        await #expect(throws: AgendaEventManager.AgendaEventError.titleChangeRequiresRename) {
            try await manager.updateEvent(changed)
        }
    }

    @Test("renameEvent renames file + lets updateEvent succeed afterwards")
    func renameThenUpdate() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        let event = makeEvent(title: "Old Title")
        try await manager.createEvent(event)

        try await manager.renameEvent(event, to: "New Title")
        let oldURL = NexusPaths.eventFileURL(forTitle: "Old Title", in: nexus)
        let newURL = NexusPaths.eventFileURL(forTitle: "New Title", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(manager.events.first?.title == "New Title")

        guard let renamed = manager.events.first(where: { $0.id == event.id }) else {
            Issue.record("Renamed event missing from manager.events")
            return
        }
        var updated = renamed
        updated.description = "added later"
        try await manager.updateEvent(updated)
        #expect(manager.events.first?.description == "added later")
    }

    @Test("deleteEvent removes file + drops from events")
    func deleteEventCase() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        let event = makeEvent(title: "X")
        try await manager.createEvent(event)
        try await manager.deleteEvent(event)
        #expect(manager.events.isEmpty)
    }

    @Test("loadAll skips non-event.json files in the Events dir")
    func loadAllFiltersExtension() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()
        // Drop a stray .task.json into Events/ to confirm it's ignored.
        let strayURL = NexusPaths.eventsDir(in: nexus)
            .appendingPathComponent("stray.task.json")
        try Data("{}".utf8).write(to: strayURL)

        await manager.loadAll()
        #expect(manager.events.isEmpty)
    }
}
