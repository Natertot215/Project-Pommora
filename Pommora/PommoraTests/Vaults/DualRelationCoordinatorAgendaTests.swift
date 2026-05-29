import Foundation
import Testing

@testable import Pommora

/// Phase 8: Tests that `DualRelationCoordinator` correctly handles Agenda Tasks
/// and Agenda Events as paired-relation targets.
///
/// All tests operate on a temp nexus (filesystem real writes) to exercise the
/// full SchemaTransaction commit path — mirroring `DualRelationCoordinatorTests`.
@Suite("DualRelationCoordinatorAgendaTests")
struct DualRelationCoordinatorAgendaTests {

    // MARK: - Helpers

    /// Creates a PageType on disk and returns it.
    @discardableResult
    private static func makePageType(
        id: String = ULID.generate(),
        title: String,
        nexus: Nexus
    ) throws -> PageType {
        let pt = PageType(
            id: id,
            title: title,
            icon: nil,
            properties: [],
            views: [],
            modifiedAt: Date()
        )
        let folder = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        let meta = NexusPaths.vaultMetadataURL(forTitle: title, in: nexus)
        try Filesystem.createFolderWithMetadata(folderURL: folder, metadataURL: meta, metadata: pt)
        return pt
    }

    /// Seeds an `AgendaTaskSchema` on disk (default seed) and returns it.
    private static func seedTaskSchema(nexus: Nexus) throws -> AgendaTaskSchema {
        let dir = NexusPaths.tasksDir(in: nexus)
        try NexusPaths.ensureDirectoryExists(dir)
        let schema = AgendaTaskSchema.defaultSeed()
        let url = NexusPaths.taskSchemaURL(in: nexus)
        try AtomicJSON.write(schema, to: url)
        return schema
    }

    /// Seeds an `AgendaEventSchema` on disk (default seed) and returns it.
    private static func seedEventSchema(nexus: Nexus) throws -> AgendaEventSchema {
        let dir = NexusPaths.eventsDir(in: nexus)
        try NexusPaths.ensureDirectoryExists(dir)
        let schema = AgendaEventSchema.defaultSeed()
        let url = NexusPaths.eventSchemaURL(in: nexus)
        try AtomicJSON.write(schema, to: url)
        return schema
    }

    /// Reloads `AgendaTaskSchema` from disk.
    private static func reloadTaskSchema(nexus: Nexus) throws -> AgendaTaskSchema {
        return try AtomicJSON.decode(AgendaTaskSchema.self, from: NexusPaths.taskSchemaURL(in: nexus))
    }

    /// Reloads `AgendaEventSchema` from disk.
    private static func reloadEventSchema(nexus: Nexus) throws -> AgendaEventSchema {
        return try AtomicJSON.decode(AgendaEventSchema.self, from: NexusPaths.eventSchemaURL(in: nexus))
    }

    // MARK: - Phase 8.1: PageType ↔ AgendaTasks paired relation

    @Test("createPairedRelation — PageType source + AgendaTasks target writes both sidecars")
    func createPairedRelationPageTypeToAgendaTasks() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let notes = try Self.makePageType(title: "Notes", nexus: nexus)
        let taskSchema = try Self.seedTaskSchema(nexus: nexus)

        let (sourceID, targetID) = try DualRelationCoordinator.createPairedRelation(
            source: .pageType(notes),
            sourcePropertyName: "RelatedTask",
            sourceScope: .agendaTasks,
            target: .agendaTasks(taskSchema),
            targetPropertyName: "Notes",
            targetScope: .pageType(notes.id),
            nexus: nexus
        )

        // Reload both sidecars from disk.
        let reloadedNotes = try PageType.load(from: NexusPaths.vaultMetadataURL(forTitle: "Notes", in: nexus))
        let reloadedTaskSchema = try Self.reloadTaskSchema(nexus: nexus)

        // Source side: property appended with correct ID and scope.
        let sourceProp = reloadedNotes.properties.first { $0.id == sourceID }
        #expect(sourceProp != nil)
        #expect(sourceProp?.name == "RelatedTask")
        #expect(sourceProp?.type == .relation)
        #expect(sourceProp?.relationTarget == .agendaTasks)
        #expect(sourceProp?.dualProperty?.syncedPropertyID == targetID)
        #expect(sourceProp?.dualProperty?.syncedPropertyDefinedOnTypeID == ReservedTypeID.agendaTasks)

        // Target side: reverse property appended on the task schema.
        let targetProp = reloadedTaskSchema.properties.first { $0.id == targetID }
        #expect(targetProp != nil)
        #expect(targetProp?.name == "Notes")
        #expect(targetProp?.type == .relation)
        #expect(targetProp?.relationTarget == .pageType(notes.id))
        #expect(targetProp?.dualProperty?.syncedPropertyID == sourceID)
        #expect(targetProp?.dualProperty?.syncedPropertyDefinedOnTypeID == notes.id)
    }

    // MARK: - Phase 8.2: PageType ↔ AgendaEvents paired relation

    @Test("createPairedRelation — PageType source + AgendaEvents target writes both sidecars")
    func createPairedRelationPageTypeToAgendaEvents() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let notes = try Self.makePageType(title: "Notes", nexus: nexus)
        let eventSchema = try Self.seedEventSchema(nexus: nexus)

        let (sourceID, targetID) = try DualRelationCoordinator.createPairedRelation(
            source: .pageType(notes),
            sourcePropertyName: "RelatedEvent",
            sourceScope: .agendaEvents,
            target: .agendaEvents(eventSchema),
            targetPropertyName: "Notes",
            targetScope: .pageType(notes.id),
            nexus: nexus
        )

        // Reload both sidecars from disk.
        let reloadedNotes = try PageType.load(from: NexusPaths.vaultMetadataURL(forTitle: "Notes", in: nexus))
        let reloadedEventSchema = try Self.reloadEventSchema(nexus: nexus)

        // Source side.
        let sourceProp = reloadedNotes.properties.first { $0.id == sourceID }
        #expect(sourceProp != nil)
        #expect(sourceProp?.name == "RelatedEvent")
        #expect(sourceProp?.type == .relation)
        #expect(sourceProp?.relationTarget == .agendaEvents)
        #expect(sourceProp?.dualProperty?.syncedPropertyID == targetID)
        #expect(sourceProp?.dualProperty?.syncedPropertyDefinedOnTypeID == ReservedTypeID.agendaEvents)

        // Target side: reverse property on the event schema.
        let targetProp = reloadedEventSchema.properties.first { $0.id == targetID }
        #expect(targetProp != nil)
        #expect(targetProp?.name == "Notes")
        #expect(targetProp?.type == .relation)
        #expect(targetProp?.relationTarget == .pageType(notes.id))
        #expect(targetProp?.dualProperty?.syncedPropertyID == sourceID)
        #expect(targetProp?.dualProperty?.syncedPropertyDefinedOnTypeID == notes.id)
    }

    // MARK: - Phase 8.3: typeID returns reserved identifiers

    @Test("TypeKind.typeID returns ReservedTypeID constants for Agenda cases")
    func typeIDReturnsReservedConstants() {
        let taskKind = DualRelationCoordinator.TypeKind.agendaTasks(AgendaTaskSchema.defaultSeed())
        let eventKind = DualRelationCoordinator.TypeKind.agendaEvents(AgendaEventSchema.defaultSeed())
        #expect(taskKind.typeID == ReservedTypeID.agendaTasks)
        #expect(eventKind.typeID == ReservedTypeID.agendaEvents)
    }
}
