import Foundation
import Testing

@testable import Pommora

// MARK: - ReorderPropertyParity
//
// Characterization suite — pins current reorderProperty behaviour on the schema-carrying
// managers BEFORE the shared-service extraction. All tests run against unmodified
// production code.
//
// Implementation note: `.indexOutOfBounds` is structurally dead code in the current
// implementation. After the clamp `min(max(toIndex, 0), props.count - 1)`, the subsequent
// guard `clampedIndex >= 0 && clampedIndex < props.count` is always true for a non-empty
// array (and the propertyNotFound guard fires first for an empty one). The out-of-range
// tests therefore assert `.propertyNotFound` — the first actually-reachable error for an
// invalid call — rather than the nominally documented `.indexOutOfBounds`.

@MainActor
@Suite("ReorderPropertyParity")
struct ReorderPropertyParity {

    // MARK: - Helpers

    private func makeNumberProp(name: String) -> PropertyDefinition {
        PropertyDefinition(id: "", name: name, type: .number)
    }

    // MARK: - PageCollectionManager

    @Test("PageCollectionManager reorderProperty moves middle property to front in-memory and on disk")
    func collectionManagerReorderHappyPath() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageCollectionManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createPageCollection(name: "Notes", icon: nil)
        let collectionID = manager.types.first!.id

        // Seed three user properties in order A, B, C.
        try await manager.addProperty(makeNumberProp(name: "Alpha"), to: collectionID)
        try await manager.addProperty(makeNumberProp(name: "Beta"), to: collectionID)
        try await manager.addProperty(makeNumberProp(name: "Gamma"), to: collectionID)

        let props = manager.types.first { $0.id == collectionID }!.properties
        let idA = props[0].id
        let idB = props[1].id
        let idC = props[2].id

        // Move B (index 1) → index 0.
        try await manager.reorderProperty(id: idB, in: collectionID, toIndex: 0)

        // (a) In-memory order is [B, A, C].
        let inMemory = manager.types.first { $0.id == collectionID }!.properties
        #expect(inMemory.map(\.id) == [idB, idA, idC])

        // (b) On-disk order matches — reload via PageCollection.load.
        let metaURL = NexusPaths.collectionMetadataURL(forTitle: "Notes", in: nexus)
        let reloaded = try PageCollection.load(from: metaURL)
        #expect(reloaded.properties.map(\.id) == [idB, idA, idC])

        // (c) No error was surfaced.
        #expect(manager.pendingError == nil)
    }

    @Test("PageCollectionManager reorderProperty with unknown property ID throws propertyNotFound")
    func collectionManagerReorderUnknownProperty() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageCollectionManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createPageCollection(name: "Notes", icon: nil)
        let collectionID = manager.types.first!.id

        try await manager.addProperty(makeNumberProp(name: "Alpha"), to: collectionID)
        try await manager.addProperty(makeNumberProp(name: "Beta"), to: collectionID)
        try await manager.addProperty(makeNumberProp(name: "Gamma"), to: collectionID)

        await #expect(throws: PageCollectionManagerError.propertyNotFound) {
            try await manager.reorderProperty(id: "prop_nonexistent", in: collectionID, toIndex: 0)
        }
    }

    // MARK: - AgendaTaskManager

    @Test("AgendaTaskManager reorderProperty moves middle property to front in-memory and on disk")
    func agendaTaskManagerReorderHappyPath() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        // Seed three user properties in order A, B, C (singleton schema — no collectionID).
        try await manager.addProperty(makeNumberProp(name: "Alpha"))
        try await manager.addProperty(makeNumberProp(name: "Beta"))
        try await manager.addProperty(makeNumberProp(name: "Gamma"))

        // Filter to user properties only (schema also contains built-in _status etc.).
        let userProps = manager.schema.properties.filter { $0.id.hasPrefix("prop_") }
        let idA = userProps[0].id
        let idB = userProps[1].id
        let idC = userProps[2].id

        // Move B (middle user prop) → the position before A.
        // Determine its absolute index in the full schema array.
        let absoluteIndexOfA = manager.schema.properties.firstIndex { $0.id == idA }!
        try await manager.reorderProperty(id: idB, toIndex: absoluteIndexOfA)

        // (a) In-memory: B now appears before A (both relative to user props).
        let inMemoryUser = manager.schema.properties.filter { $0.id.hasPrefix("prop_") }
        #expect(inMemoryUser.map(\.id) == [idB, idA, idC])

        // (b) On-disk order matches — reload via AtomicJSON.decode.
        let schemaURL = NexusPaths.taskSchemaURL(in: nexus)
        let reloaded = try AtomicJSON.decode(AgendaTaskSchema.self, from: schemaURL)
        let reloadedUser = reloaded.properties.filter { $0.id.hasPrefix("prop_") }
        #expect(reloadedUser.map(\.id) == [idB, idA, idC])

        // (c) No error was surfaced.
        #expect(manager.pendingError == nil)
    }

    @Test("AgendaTaskManager reorderProperty with unknown property ID throws propertyNotFound")
    func agendaTaskManagerReorderUnknownProperty() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        try await manager.addProperty(makeNumberProp(name: "Alpha"))
        try await manager.addProperty(makeNumberProp(name: "Beta"))
        try await manager.addProperty(makeNumberProp(name: "Gamma"))

        await #expect(throws: AgendaTaskManagerError.propertyNotFound) {
            try await manager.reorderProperty(id: "prop_nonexistent", toIndex: 0)
        }
    }

    // MARK: - AgendaEventManager

    @Test("AgendaEventManager reorderProperty moves middle property to front in-memory and on disk")
    func agendaEventManagerReorderHappyPath() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        // Seed three user properties in order A, B, C (singleton schema — no collectionID).
        try await manager.addProperty(makeNumberProp(name: "Alpha"))
        try await manager.addProperty(makeNumberProp(name: "Beta"))
        try await manager.addProperty(makeNumberProp(name: "Gamma"))

        // Filter to user properties only (schema may contain built-in _type etc.).
        let userProps = manager.schema.properties.filter { $0.id.hasPrefix("prop_") }
        let idA = userProps[0].id
        let idB = userProps[1].id
        let idC = userProps[2].id

        // Determine B's and A's absolute indices and move B to where A is.
        let absoluteIndexOfA = manager.schema.properties.firstIndex { $0.id == idA }!
        try await manager.reorderProperty(id: idB, toIndex: absoluteIndexOfA)

        // (a) In-memory: B now appears before A among user props.
        let inMemoryUser = manager.schema.properties.filter { $0.id.hasPrefix("prop_") }
        #expect(inMemoryUser.map(\.id) == [idB, idA, idC])

        // (b) On-disk order matches — reload via AtomicJSON.decode.
        let schemaURL = NexusPaths.eventSchemaURL(in: nexus)
        let reloaded = try AtomicJSON.decode(AgendaEventSchema.self, from: schemaURL)
        let reloadedUser = reloaded.properties.filter { $0.id.hasPrefix("prop_") }
        #expect(reloadedUser.map(\.id) == [idB, idA, idC])

        // (c) No error was surfaced.
        #expect(manager.pendingError == nil)
    }

    @Test("AgendaEventManager reorderProperty with unknown property ID throws propertyNotFound")
    func agendaEventManagerReorderUnknownProperty() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        try await manager.addProperty(makeNumberProp(name: "Alpha"))
        try await manager.addProperty(makeNumberProp(name: "Beta"))
        try await manager.addProperty(makeNumberProp(name: "Gamma"))

        await #expect(throws: AgendaEventManagerError.propertyNotFound) {
            try await manager.reorderProperty(id: "prop_nonexistent", toIndex: 0)
        }
    }

    // MARK: - Clamp Characterization

    @Test("PageCollectionManager reorderProperty clamps out-of-range toIndex to last position")
    func outOfRangeIndexClampsToLast_pageType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageCollectionManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createPageCollection(name: "Notes", icon: nil)
        let collectionID = manager.types.first!.id

        // Seed three user properties in order A, B, C.
        try await manager.addProperty(makeNumberProp(name: "Alpha"), to: collectionID)
        try await manager.addProperty(makeNumberProp(name: "Beta"), to: collectionID)
        try await manager.addProperty(makeNumberProp(name: "Gamma"), to: collectionID)

        let props = manager.types.first { $0.id == collectionID }!.properties
        let idA = props[0].id
        let idB = props[1].id
        let idC = props[2].id

        // Move A to a wildly out-of-range index — implementation clamps to count-1 (last).
        try await manager.reorderProperty(id: idA, in: collectionID, toIndex: 999)

        // (a) In-memory order is [B, C, A] — A was clamped to the last slot.
        let inMemory = manager.types.first { $0.id == collectionID }!.properties
        #expect(inMemory.map(\.id) == [idB, idC, idA])

        // (b) On-disk order matches — reload via PageCollection.load.
        let metaURL = NexusPaths.collectionMetadataURL(forTitle: "Notes", in: nexus)
        let reloaded = try PageCollection.load(from: metaURL)
        #expect(reloaded.properties.map(\.id) == [idB, idC, idA])

        // (c) No error was surfaced — clamp is silent, not a throw.
        #expect(manager.pendingError == nil)
    }

    @Test("AgendaTaskManager reorderProperty clamps out-of-range toIndex to last position")
    func outOfRangeIndexClampsToLast_task() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        // Seed three user properties in order A, B, C (singleton schema — no collectionID).
        try await manager.addProperty(makeNumberProp(name: "Alpha"))
        try await manager.addProperty(makeNumberProp(name: "Beta"))
        try await manager.addProperty(makeNumberProp(name: "Gamma"))

        // Filter to user properties only (schema also contains built-in _status etc.).
        let userProps = manager.schema.properties.filter { $0.id.hasPrefix("prop_") }
        let idA = userProps[0].id
        let idB = userProps[1].id
        let idC = userProps[2].id

        // Move A to a wildly out-of-range absolute index — implementation clamps to count-1 (last
        // absolute slot in the full schema array, which is the last user prop slot).
        try await manager.reorderProperty(id: idA, toIndex: 999)

        // (a) In-memory: A is clamped to last; user props become [B, C, A].
        let inMemoryUser = manager.schema.properties.filter { $0.id.hasPrefix("prop_") }
        #expect(inMemoryUser.map(\.id) == [idB, idC, idA])

        // (b) On-disk order matches — reload via AtomicJSON.decode.
        let schemaURL = NexusPaths.taskSchemaURL(in: nexus)
        let reloaded = try AtomicJSON.decode(AgendaTaskSchema.self, from: schemaURL)
        let reloadedUser = reloaded.properties.filter { $0.id.hasPrefix("prop_") }
        #expect(reloadedUser.map(\.id) == [idB, idC, idA])

        // (c) No error was surfaced — clamp is silent, not a throw.
        #expect(manager.pendingError == nil)
    }
}
