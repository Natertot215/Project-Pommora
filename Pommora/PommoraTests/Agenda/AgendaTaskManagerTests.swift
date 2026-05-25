import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("AgendaTaskManager")
struct AgendaTaskManagerTests {

    @Test("loadAll eagerly seeds <nexus>/Tasks/_taskconfig.json on a fresh Nexus")
    func seedsSchema() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()
        // Eager creation per locked decision #9: folder + sidecar materialize at
        // the default name `<nexus>/Tasks/` and discovery sticks to it on
        // subsequent loads.
        let tasksDir = NexusPaths.tasksDir(in: nexus)
        #expect(tasksDir.lastPathComponent == "Tasks")
        #expect(tasksDir.deletingLastPathComponent().path == nexus.rootURL.path)
        let schemaURL = NexusPaths.taskSchemaURL(in: nexus)
        #expect(schemaURL.lastPathComponent == NexusPaths.taskConfigSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: schemaURL.path))
        let loaded = try AtomicJSON.decode(AgendaTaskSchema.self, from: schemaURL)
        #expect(loaded.properties.contains { $0.id == "_type" && $0.name == "type" })
    }

    @Test("loadAll reuses a renamed Tasks singleton discovered by _taskconfig.json")
    func loadAllReusesRenamedSingleton() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Pre-seed a renamed Tasks singleton with the canonical schema content.
        let renamed = nexus.rootURL.appendingPathComponent("Errands", isDirectory: true)
        try FileManager.default.createDirectory(at: renamed, withIntermediateDirectories: true)
        try AtomicJSON.write(
            AgendaTaskSchema.defaultSeed(),
            to: renamed.appendingPathComponent(NexusPaths.taskConfigSidecarFilename)
        )

        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        // Discovery picks the renamed folder; default <nexus>/Tasks/ is NOT created.
        #expect(NexusPaths.tasksDir(in: nexus).path == renamed.path)
        let defaultFolder = nexus.rootURL.appendingPathComponent("Tasks", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: defaultFolder.path))
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
