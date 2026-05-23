import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("AgendaTaskManager")
struct AgendaTaskManagerTests {

    @Test("loadAll seeds Tasks/_schema.json if missing")
    func seedsSchema() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()
        let schemaURL = NexusPaths.taskSchemaURL(in: nexus)
        #expect(FileManager.default.fileExists(atPath: schemaURL.path))
        let loaded = try AtomicJSON.decode(AgendaTaskSchema.self, from: schemaURL)
        #expect(loaded.properties.contains { $0.name == "type" && $0.builtin })
    }

    @Test("createTask writes .task.json with type=Task")
    func createTask() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        let task = AgendaTask(
            id: ULID.generate(),
            title: "Buy groceries",
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
            properties: ["type": .select("Task")]
        )
        try await manager.createTask(task)
        let url = NexusPaths.taskFileURL(forTitle: "Buy groceries", in: nexus)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(manager.tasks.count == 1)
    }

    @Test("createTask with invalid type throws")
    func invalidType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        let task = AgendaTask(
            id: ULID.generate(),
            title: "X",
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
            properties: ["type": .select("Bogus")]
        )
        await #expect(throws: AgendaTaskValidator.ValidationError.unknownTypeValue("Bogus")) {
            try await manager.createTask(task)
        }
    }

    @Test("updateTask refuses title changes — must use renameTask first")
    func updateTaskRefusesTitleChange() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        let id = ULID.generate()
        let task = AgendaTask(
            id: id,
            title: "Original",
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
            properties: ["type": .select("Task")]
        )
        try await manager.createTask(task)

        var changed = task
        changed.title = "Renamed-without-rename"
        await #expect(throws: AgendaTaskManager.AgendaTaskError.titleChangeRequiresRename) {
            try await manager.updateTask(changed)
        }
    }

    @Test("renameTask renames file + lets updateTask succeed afterwards")
    func renameThenUpdate() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        let task = AgendaTask(
            id: ULID.generate(),
            title: "Old Title",
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
            properties: ["type": .select("Task")]
        )
        try await manager.createTask(task)

        try await manager.renameTask(task, to: "New Title")
        let oldURL = NexusPaths.taskFileURL(forTitle: "Old Title", in: nexus)
        let newURL = NexusPaths.taskFileURL(forTitle: "New Title", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(manager.tasks.first?.title == "New Title")

        guard let renamed = manager.tasks.first(where: { $0.id == task.id }) else {
            Issue.record("Renamed task missing from manager.tasks")
            return
        }
        var updated = renamed
        updated.description = "added later"
        try await manager.updateTask(updated)
        #expect(manager.tasks.first?.description == "added later")
    }

    @Test("deleteTask removes file + drops from tasks")
    func deleteTask() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        let task = AgendaTask(
            id: ULID.generate(),
            title: "X",
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
            properties: ["type": .select("Task")]
        )
        try await manager.createTask(task)
        try await manager.deleteTask(task)
        #expect(manager.tasks.isEmpty)
    }

    @Test("loadAll skips non-task.json files in the Tasks dir")
    func loadAllFiltersExtension() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()
        // Drop a stray .event.json into Tasks/ to confirm it's ignored.
        let strayURL = NexusPaths.tasksDir(in: nexus)
            .appendingPathComponent("stray.event.json")
        try Data("{}".utf8).write(to: strayURL)

        await manager.loadAll()
        #expect(manager.tasks.isEmpty)
    }
}
