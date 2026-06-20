import Foundation
import Testing

@testable import Pommora

/// G.3: Tests that `loadAll` injects `_status` when an existing sidecar lacks it,
/// and that the injection is idempotent on subsequent loads.
@MainActor
@Suite("AgendaStatusBackfill")
struct AgendaStatusBackfillTests {

    // MARK: - Helpers

    /// Writes a `_taskconfig.json` that matches the Phase-C schema shape: properties
    /// present but no `_status` among them (e.g., legacy `_type` Select only).
    private static func writeTaskConfigWithoutStatus(in nexus: Nexus) throws {
        let dir = NexusPaths.tasksDir(in: nexus)
        try NexusPaths.ensureDirectoryExists(dir)
        let schemaURL = NexusPaths.taskSchemaURL(in: nexus)

        // Build a minimal schema without _status. Use AtomicJSON-compatible encoding
        // (ISO8601 dates) via a hand-constructed AgendaTaskSchema so the sidecar
        // roundtrips through the real decoder without format errors.
        let typeOnlyDef = PropertyDefinition(
            id: "_type",
            name: "type",
            type: .select,
            selectOptions: [PropertyDefinition.SelectOption(value: "Task", label: "Task", color: .blue)]
        )
        // Build a raw JSON blob directly — AgendaTaskSchema doesn't have a public
        // memberwise init exposed for arbitrary property lists, so encode by hand.
        let schemaJSON = """
        {
          "schemaVersion": 1,
          "icon": "checkmark.circle",
          "properties": [
            {
              "id": "_type",
              "name": "type",
              "type": "select",
              "select_options": [
                {"value": "Task", "label": "Task", "color": "blue"}
              ]
            }
          ],
          "views": [],
          "modified_at": "\(ISO8601DateFormatter().string(from: Date()))"
        }
        """
        try Data(schemaJSON.utf8).write(to: schemaURL, options: [.atomic])
        _ = typeOnlyDef  // silence unused-variable warning
    }

    /// Writes a `_eventconfig.json` that lacks `_status`.
    private static func writeEventConfigWithoutStatus(in nexus: Nexus) throws {
        let dir = NexusPaths.eventsDir(in: nexus)
        try NexusPaths.ensureDirectoryExists(dir)
        let schemaURL = NexusPaths.eventSchemaURL(in: nexus)

        let schemaJSON = """
        {
          "schemaVersion": 1,
          "icon": "calendar",
          "properties": [
            {
              "id": "_type",
              "name": "type",
              "type": "select",
              "select_options": [
                {"value": "Event", "label": "Event", "color": "green"}
              ]
            }
          ],
          "views": [],
          "modified_at": "\(ISO8601DateFormatter().string(from: Date()))"
        }
        """
        try Data(schemaJSON.utf8).write(to: schemaURL, options: [.atomic])
    }

    // MARK: - AgendaTaskManager backfill

    @Test("loadAll injects _status into task schema that lacks it")
    func taskLoadAllBackfillsStatus() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Pre-seed a _taskconfig.json without _status.
        try Self.writeTaskConfigWithoutStatus(in: nexus)

        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        // In-memory schema must have _status prepended.
        let statusProp = manager.schema.properties.first { $0.id == "_status" }
        #expect(statusProp != nil)
        #expect(statusProp?.type == .status)
        #expect(statusProp?.statusGroups?.isEmpty == false)

        // On-disk sidecar must have been rewritten with _status.
        let schemaURL = NexusPaths.taskSchemaURL(in: nexus)
        let onDisk = try AtomicJSON.decode(AgendaTaskSchema.self, from: schemaURL)
        #expect(onDisk.properties.contains { $0.id == "_status" })
    }

    @Test("loadAll backfill is idempotent — second load is a no-op")
    func taskLoadAllBackfillIsIdempotent() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        try Self.writeTaskConfigWithoutStatus(in: nexus)

        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        let schemaURL = NexusPaths.taskSchemaURL(in: nexus)
        let afterFirst = try Data(contentsOf: schemaURL)

        await manager.loadAll()

        let afterSecond = try Data(contentsOf: schemaURL)
        // File bytes must be identical — no redundant rewrite on the second load.
        #expect(afterFirst == afterSecond)
    }

    @Test("loadAll does not double-insert _status when already present")
    func taskLoadAllDoesNotDuplicateStatus() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        let statusCount = manager.schema.properties.filter { $0.id == "_status" }.count
        #expect(statusCount == 1)
    }

    // MARK: - AgendaEventManager backfill

    @Test("loadAll injects _status into event schema that lacks it")
    func eventLoadAllBackfillsStatus() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        try Self.writeEventConfigWithoutStatus(in: nexus)

        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        let statusProp = manager.schema.properties.first { $0.id == "_status" }
        #expect(statusProp != nil)
        #expect(statusProp?.type == .status)
        #expect(statusProp?.statusGroups?.isEmpty == false)

        let schemaURL = NexusPaths.eventSchemaURL(in: nexus)
        let onDisk = try AtomicJSON.decode(AgendaEventSchema.self, from: schemaURL)
        #expect(onDisk.properties.contains { $0.id == "_status" })
    }

    @Test("loadAll event backfill is idempotent — second load is a no-op")
    func eventLoadAllBackfillIsIdempotent() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        try Self.writeEventConfigWithoutStatus(in: nexus)

        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        let schemaURL = NexusPaths.eventSchemaURL(in: nexus)
        let afterFirst = try Data(contentsOf: schemaURL)

        await manager.loadAll()

        let afterSecond = try Data(contentsOf: schemaURL)
        #expect(afterFirst == afterSecond)
    }
}
