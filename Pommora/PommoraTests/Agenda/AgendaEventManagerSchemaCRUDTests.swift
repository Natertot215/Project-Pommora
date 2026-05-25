import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("AgendaEventManagerSchemaCRUD")
struct AgendaEventManagerSchemaCRUDTests {

    // MARK: - Helper

    private func makeTextProp(name: String = "Notes") -> PropertyDefinition {
        PropertyDefinition(id: "", name: name, type: .url)
    }

    private func makeEvent(title: String, startAt: Date, endAt: Date) -> AgendaEvent {
        let now = Date()
        return AgendaEvent(
            id: ULID.generate(),
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
            tier1: [], tier2: [], tier3: [],
            createdAt: now, modifiedAt: now,
            properties: ["type": .select("Event")]
        )
    }

    // MARK: - Test 1: addProperty mints ID and persists

    @Test("addProperty with empty id mints prop_ ID and persists to sidecar")
    func addPropertyMintsIDAndPersists() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        // Pass id: "" — addProperty should mint a new ID.
        let def = PropertyDefinition(id: "", name: "Venue", type: .url)
        try await manager.addProperty(def)

        // In-memory: defaultSeed has 1 builtin (_status) + the new one.
        let userProps = manager.schema.properties.filter { $0.id.hasPrefix("prop_") }
        #expect(userProps.count == 1)
        let stored = userProps[0]
        #expect(stored.name == "Venue")
        #expect(stored.id.hasPrefix("prop_"))

        // On-disk: reload sidecar and verify.
        let schemaURL = NexusPaths.eventSchemaURL(in: nexus)
        let reloaded = try AtomicJSON.decode(AgendaEventSchema.self, from: schemaURL)
        let reloadedUserProps = reloaded.properties.filter { $0.id.hasPrefix("prop_") }
        #expect(reloadedUserProps.count == 1)
        #expect(reloadedUserProps[0].name == "Venue")
        #expect(reloadedUserProps[0].id.hasPrefix("prop_"))
    }

    // MARK: - Test 2: rename does not rewrite member files

    @Test("renameProperty updates schema only — event files are untouched")
    func renameDoesNotRewriteMemberFiles() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        let prop = PropertyDefinition(id: ReservedPropertyID.mintUserPropertyID(), name: "Score", type: .number)
        try await manager.addProperty(prop)
        let storedPropID = manager.schema.properties.first { $0.name == "Score" }!.id

        // Write a fake .event.json file referencing the property.
        let now = Date()
        let start = now
        let end = now.addingTimeInterval(3600)
        let event = AgendaEvent(
            id: ULID.generate(),
            title: "TestEvent",
            icon: nil,
            description: "",
            startAt: start,
            endAt: end,
            allDay: false,
            location: nil,
            recurrence: nil,
            alarmOffsets: [],
            alarmAbsolute: [],
            calendarID: nil,
            eventkitUUID: nil,
            tier1: [], tier2: [], tier3: [],
            createdAt: now, modifiedAt: now,
            properties: [storedPropID: .number(42), "type": .select("Event")]
        )
        let eventURL = NexusPaths.eventFileURL(forTitle: "TestEvent", in: nexus)
        try AtomicJSON.write(event, to: eventURL)

        // Capture file data before rename.
        let dataBefore = try Data(contentsOf: eventURL)

        // Rename the property (schema-only).
        try await manager.renameProperty(id: storedPropID, to: "Rating")

        // Member file must be byte-identical.
        let dataAfter = try Data(contentsOf: eventURL)
        #expect(dataBefore == dataAfter)

        // Schema in-memory and on-disk must reflect new name.
        let renamedProp = manager.schema.properties.first { $0.id == storedPropID }
        #expect(renamedProp?.name == "Rating")
        let schemaURL = NexusPaths.eventSchemaURL(in: nexus)
        let reloaded = try AtomicJSON.decode(AgendaEventSchema.self, from: schemaURL)
        #expect(reloaded.properties.first { $0.id == storedPropID }?.name == "Rating")
    }

    // MARK: - Test 3: changeType same type is lossless (no confirmation needed)

    @Test("changeType same type is treated as lossless — no throw")
    func changeTypeSameTypeNoOpIsLossless() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        let prop = PropertyDefinition(id: ReservedPropertyID.mintUserPropertyID(), name: "Score", type: .number)
        try await manager.addProperty(prop)
        let storedPropID = manager.schema.properties.first { $0.name == "Score" }!.id

        // number → number: should succeed without dropConflictingValues.
        try await manager.changeType(of: storedPropID, to: .number, dropConflictingValues: false)

        #expect(manager.schema.properties.first { $0.id == storedPropID }?.type == .number)
    }

    // MARK: - Test 4: changeType lossy with dropConflictingValues strips member-file values

    @Test("changeType lossy with dropConflictingValues=true removes value from event files")
    func changeTypeLossyDropsValuesViaSchemaTransaction() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        let prop = PropertyDefinition(id: ReservedPropertyID.mintUserPropertyID(), name: "Score", type: .number)
        try await manager.addProperty(prop)
        let storedPropID = manager.schema.properties.first { $0.name == "Score" }!.id

        // Write a fake .event.json file with a numeric value for the property.
        let now = Date()
        let event = AgendaEvent(
            id: ULID.generate(),
            title: "Entry1",
            icon: nil,
            description: "",
            startAt: now,
            endAt: now.addingTimeInterval(3600),
            allDay: false,
            location: nil,
            recurrence: nil,
            alarmOffsets: [],
            alarmAbsolute: [],
            calendarID: nil,
            eventkitUUID: nil,
            tier1: [], tier2: [], tier3: [],
            createdAt: now, modifiedAt: now,
            properties: [storedPropID: .number(99), "type": .select("Event")]
        )
        let eventURL = NexusPaths.eventFileURL(forTitle: "Entry1", in: nexus)
        try AtomicJSON.write(event, to: eventURL)

        // Change number → checkbox, with value drop.
        try await manager.changeType(of: storedPropID, to: .checkbox, dropConflictingValues: true)

        // Schema: property type updated.
        #expect(manager.schema.properties.first { $0.id == storedPropID }?.type == .checkbox)

        // Member file: property key must be GONE.
        let reloadedEvent = try AgendaEvent.load(from: eventURL)
        #expect(reloadedEvent.properties[storedPropID] == nil)
    }

    // MARK: - Test 5: delete _status built-in property throws

    @Test("deleteProperty on _status built-in throws cannotDeleteBuiltinProperty")
    func deleteStatusPropertyThrows() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        // _status is seeded by defaultSeed() and must not be deletable.
        await #expect(throws: AgendaEventManagerError.cannotDeleteBuiltinProperty) {
            try await manager.deleteProperty(id: "_status")
        }
    }
}
