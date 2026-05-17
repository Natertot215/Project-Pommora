import Foundation
import Testing
@testable import Pommora

@MainActor
@Suite("AgendaManager")
struct AgendaManagerTests {

    @Test("loadAll seeds _agenda.json schema if missing")
    func seedsSchema() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaManager(nexus: nexus)
        await manager.loadAll()
        let schemaURL = NexusPaths.agendaSchemaURL(in: nexus)
        #expect(FileManager.default.fileExists(atPath: schemaURL.path))
        let loaded = try AtomicJSON.decode(AgendaSchema.self, from: schemaURL)
        #expect(loaded.properties.contains { $0.name == "type" && $0.builtin })
    }

    @Test("createItem writes .agenda.json with type=Task")
    func createTask() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaManager(nexus: nexus)
        await manager.loadAll()

        let item = AgendaItem(
            id: ULID.generate(), title: "Buy groceries", icon: nil,
            startAt: nil, endAt: nil, allDay: false,
            dueAt: nil, dueFloating: false, dueAllDay: false,
            completed: false, completedAt: nil,
            location: nil, recurrence: nil,
            alarmOffsets: [], alarmAbsolute: [],
            syncTarget: nil, calendarID: nil, eventkitUUID: nil,
            description: "",
            tier1: [], tier2: [], tier3: [],
            createdAt: Date(), modifiedAt: Date(),
            properties: ["type": .select("Task")]
        )
        try await manager.createItem(item)
        let url = NexusPaths.agendaItemFileURL(forTitle: "Buy groceries", in: nexus)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(manager.items.count == 1)
    }

    @Test("createItem with invalid type throws")
    func invalidType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaManager(nexus: nexus)
        await manager.loadAll()

        let item = AgendaItem(
            id: ULID.generate(), title: "X", icon: nil,
            startAt: nil, endAt: nil, allDay: false,
            dueAt: nil, dueFloating: false, dueAllDay: false,
            completed: false, completedAt: nil,
            location: nil, recurrence: nil,
            alarmOffsets: [], alarmAbsolute: [],
            syncTarget: nil, calendarID: nil, eventkitUUID: nil,
            description: "",
            tier1: [], tier2: [], tier3: [],
            createdAt: Date(), modifiedAt: Date(),
            properties: ["type": .select("Bogus")]
        )
        await #expect(throws: AgendaValidator.ValidationError.unknownTypeValue("Bogus")) {
            try await manager.createItem(item)
        }
    }

    @Test("deleteItem removes file + drops from items")
    func deleteItem() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaManager(nexus: nexus)
        await manager.loadAll()

        let item = AgendaItem(
            id: ULID.generate(), title: "X", icon: nil,
            startAt: nil, endAt: nil, allDay: false,
            dueAt: nil, dueFloating: false, dueAllDay: false,
            completed: false, completedAt: nil,
            location: nil, recurrence: nil,
            alarmOffsets: [], alarmAbsolute: [],
            syncTarget: nil, calendarID: nil, eventkitUUID: nil,
            description: "",
            tier1: [], tier2: [], tier3: [],
            createdAt: Date(), modifiedAt: Date(),
            properties: ["type": .select("Task")]
        )
        try await manager.createItem(item)
        try await manager.deleteItem(item)
        #expect(manager.items.isEmpty)
    }
}
