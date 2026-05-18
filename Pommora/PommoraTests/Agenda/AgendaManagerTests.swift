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

    @Test("updateItem refuses title changes — must use renameAgendaItem first")
    func updateItemRefusesTitleChange() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaManager(nexus: nexus)
        await manager.loadAll()

        let id = ULID.generate()
        let item = AgendaItem(
            id: id, title: "Original", icon: nil,
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

        var changed = item
        changed.title = "Renamed-without-rename"
        await #expect(throws: AgendaManager.AgendaError.titleChangeRequiresRename) {
            try await manager.updateItem(changed)
        }
    }

    @Test("renameAgendaItem renames file + lets updateItem succeed afterwards")
    func renameThenUpdate() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaManager(nexus: nexus)
        await manager.loadAll()

        let item = AgendaItem(
            id: ULID.generate(), title: "Old Title", icon: nil,
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

        try await manager.renameAgendaItem(item, to: "New Title")
        let oldURL = NexusPaths.agendaItemFileURL(forTitle: "Old Title", in: nexus)
        let newURL = NexusPaths.agendaItemFileURL(forTitle: "New Title", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(manager.items.first?.title == "New Title")

        // updateItem now succeeds because the in-memory record's title matches
        // the (renamed) `item` we pass back in.
        guard let renamed = manager.items.first(where: { $0.id == item.id }) else {
            Issue.record("Renamed item missing from manager.items")
            return
        }
        var updated = renamed
        updated.description = "added later"
        try await manager.updateItem(updated)
        #expect(manager.items.first?.description == "added later")
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
