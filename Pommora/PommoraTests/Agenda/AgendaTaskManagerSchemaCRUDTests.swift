import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("AgendaTaskManagerSchemaCRUD")
struct AgendaTaskManagerSchemaCRUDTests {

    // MARK: - Helper

    private func makeUrlProp(name: String = "Notes") -> PropertyDefinition {
        PropertyDefinition(id: "", name: name, type: .url)
    }

    // MARK: - Test 1: addProperty mints ID and persists

    @Test("addProperty with empty id mints prop_ ID and persists to sidecar")
    func addPropertyMintsIDAndPersists() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        // Pass id: "" — addProperty should mint a new ID.
        let def = PropertyDefinition(id: "", name: "Priority", type: .number)
        try await manager.addProperty(def)

        // In-memory: defaultSeed has 1 builtin (_status) + the new one.
        let userProps = manager.schema.properties.filter { $0.id.hasPrefix("prop_") }
        #expect(userProps.count == 1)
        let stored = userProps[0]
        #expect(stored.name == "Priority")
        #expect(stored.id.hasPrefix("prop_"))

        let schemaURL = NexusPaths.taskSchemaURL(in: nexus)
        let reloaded = try AtomicJSON.decode(AgendaTaskSchema.self, from: schemaURL)
        let reloadedUserProps = reloaded.properties.filter { $0.id.hasPrefix("prop_") }
        #expect(reloadedUserProps.count == 1)
        #expect(reloadedUserProps[0].name == "Priority")
        #expect(reloadedUserProps[0].id.hasPrefix("prop_"))
    }

    // MARK: - Test 2: rename does not rewrite member files

    @Test("renameProperty updates schema only — task files are untouched")
    func renameDoesNotRewriteMemberFiles() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        let prop = PropertyDefinition(id: ReservedPropertyID.mintUserPropertyID(), name: "Score", type: .number)
        try await manager.addProperty(prop)
        let storedPropID = manager.schema.properties.first { $0.name == "Score" }!.id

        let taskURL = NexusPaths.taskFileURL(forTitle: "TestTask", in: nexus)
        let now = Date()
        let task = AgendaTask(
            id: ULID.generate(),
            title: "TestTask",
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
            tier1: [], tier2: [], tier3: [],
            createdAt: now, modifiedAt: now,
            properties: [storedPropID: .number(42), "type": .select("Task")]
        )
        try AtomicJSON.write(task, to: taskURL)

        let dataBefore = try Data(contentsOf: taskURL)

        try await manager.renameProperty(id: storedPropID, to: "Rating")

        // Member file must be byte-identical.
        let dataAfter = try Data(contentsOf: taskURL)
        #expect(dataBefore == dataAfter)

        // Schema in-memory and on-disk must reflect new name.
        let renamedProp = manager.schema.properties.first { $0.id == storedPropID }
        #expect(renamedProp?.name == "Rating")
        let schemaURL = NexusPaths.taskSchemaURL(in: nexus)
        let reloaded = try AtomicJSON.decode(AgendaTaskSchema.self, from: schemaURL)
        #expect(reloaded.properties.first { $0.id == storedPropID }?.name == "Rating")
    }

    // MARK: - Test 3: changeType same type is lossless (no confirmation needed)

    @Test("changeType same type is treated as lossless — no throw")
    func changeTypeSameTypeNoOpIsLossless() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        let prop = PropertyDefinition(id: ReservedPropertyID.mintUserPropertyID(), name: "Score", type: .number)
        try await manager.addProperty(prop)
        let storedPropID = manager.schema.properties.first { $0.name == "Score" }!.id

        // number → number: should succeed without dropConflictingValues.
        try await manager.changeType(of: storedPropID, to: .number, dropConflictingValues: false)

        #expect(manager.schema.properties.first { $0.id == storedPropID }?.type == .number)
    }

    // MARK: - Test 4: changeType lossy with dropConflictingValues strips member-file values

    @Test("changeType lossy with dropConflictingValues=true removes value from task files")
    func changeTypeLossyDropsValuesViaSchemaTransaction() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        let prop = PropertyDefinition(id: ReservedPropertyID.mintUserPropertyID(), name: "Score", type: .number)
        try await manager.addProperty(prop)
        let storedPropID = manager.schema.properties.first { $0.name == "Score" }!.id

        let taskURL = NexusPaths.taskFileURL(forTitle: "Entry1", in: nexus)
        let now = Date()
        let task = AgendaTask(
            id: ULID.generate(),
            title: "Entry1",
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
            tier1: [], tier2: [], tier3: [],
            createdAt: now, modifiedAt: now,
            properties: [storedPropID: .number(99), "type": .select("Task")]
        )
        try AtomicJSON.write(task, to: taskURL)

        try await manager.changeType(of: storedPropID, to: .checkbox, dropConflictingValues: true)

        #expect(manager.schema.properties.first { $0.id == storedPropID }?.type == .checkbox)

        // Member file: property key must be GONE.
        let reloadedTask = try AgendaTask.load(from: taskURL)
        #expect(reloadedTask.properties[storedPropID] == nil)
    }

    // MARK: - Test 5: delete _status built-in property throws

    @Test("deleteProperty on _status built-in throws cannotDeleteBuiltinProperty")
    func deleteStatusPropertyThrows() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        // _status is seeded by defaultSeed() and must not be deletable.
        await #expect(throws: AgendaTaskManagerError.cannotDeleteBuiltinProperty) {
            try await manager.deleteProperty(id: "_status")
        }
    }

    // MARK: - Test 6: deleteProperty strips value from member task files (B2.0.2)

    @Test("deleteProperty removes the property key from every .task.json member file")
    func deleteUserPropertyStripsMemberValues() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        let def = PropertyDefinition(id: "", name: "Notes", type: .url)
        try await manager.addProperty(def)
        let storedPropID = manager.schema.properties.first { $0.id.hasPrefix("prop_") }!.id

        // Mirrors the exact directory + extension that deleteProperty's strip
        // loop iterates: NexusPaths.tasksDir(in:) + suffix ".task.json".
        let taskURL = NexusPaths.taskFileURL(forTitle: "MemberTask", in: nexus)
        let now = Date()
        let task = AgendaTask(
            id: ULID.generate(),
            title: "MemberTask",
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
            tier1: [], tier2: [], tier3: [],
            createdAt: now, modifiedAt: now,
            properties: [storedPropID: .url(URL(string: "https://example.com")!), "type": .select("Task")]
        )
        try AtomicJSON.write(task, to: taskURL)

        // Schema strip + member-file strip should both fire.
        try await manager.deleteProperty(id: storedPropID)

        #expect(manager.schema.properties.first { $0.id == storedPropID } == nil)

        let reloadedTask = try AgendaTask.load(from: taskURL)
        #expect(reloadedTask.properties[storedPropID] == nil)

        #expect(manager.pendingError == nil)
    }

    // MARK: - Test 7: changeType lossy without confirmation throws (B2.0.3)

    @Test("changeType lossy without dropConflictingValues throws lossyChangeRequiresConfirmation")
    func changeTypeLossyWithoutConfirmThrows() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        let prop = PropertyDefinition(id: "", name: "Score", type: .number)
        try await manager.addProperty(prop)
        let storedPropID = manager.schema.properties.first { $0.id.hasPrefix("prop_") }!.id

        let taskURL = NexusPaths.taskFileURL(forTitle: "ScoredTask", in: nexus)
        let now = Date()
        let task = AgendaTask(
            id: ULID.generate(),
            title: "ScoredTask",
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
            tier1: [], tier2: [], tier3: [],
            createdAt: now, modifiedAt: now,
            properties: [storedPropID: .number(7), "type": .select("Task")]
        )
        try AtomicJSON.write(task, to: taskURL)

        // number → checkbox is a lossy cross-type change; without confirmation it must throw.
        await #expect(throws: AgendaTaskManagerError.lossyChangeRequiresConfirmation) {
            try await manager.changeType(of: storedPropID, to: .checkbox, dropConflictingValues: false)
        }
    }
}
