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

        // In-memory: defaultSeed has 1 builtin (_type) + the new one.
        let userProps = manager.schema.properties.filter { $0.id.hasPrefix("prop_") }
        #expect(userProps.count == 1)
        let stored = userProps[0]
        #expect(stored.name == "Priority")
        #expect(stored.id.hasPrefix("prop_"))

        // On-disk: reload sidecar and verify.
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

        // Write a fake .task.json file referencing the property.
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

        // Capture file data before rename.
        let dataBefore = try Data(contentsOf: taskURL)

        // Rename the property (schema-only).
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

        // Write a fake .task.json file with a numeric value for the property.
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

        // Change number → checkbox, with value drop.
        try await manager.changeType(of: storedPropID, to: .checkbox, dropConflictingValues: true)

        // Schema: property type updated.
        #expect(manager.schema.properties.first { $0.id == storedPropID }?.type == .checkbox)

        // Member file: property key must be GONE.
        let reloadedTask = try AgendaTask.load(from: taskURL)
        #expect(reloadedTask.properties[storedPropID] == nil)
    }

    // MARK: - Test 5: delete _type built-in property throws

    @Test("deleteProperty on _type built-in throws cannotDeleteBuiltinProperty")
    func deleteTypePropertyThrows() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        // _type is seeded by defaultSeed() and must not be deletable.
        await #expect(throws: AgendaTaskManagerError.cannotDeleteBuiltinProperty) {
            try await manager.deleteProperty(id: "_type")
        }
    }
}
