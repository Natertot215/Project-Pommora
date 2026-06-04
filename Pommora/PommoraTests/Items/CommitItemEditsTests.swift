import Foundation
import Testing

@testable import Pommora

/// T4.5 — `ItemContentManager.commitItemEdits` is the testable persist seam the
/// LIVE Item Window's `commitSave` routes through. It applies the window's draft
/// title / icon / description / properties onto an Item and persists via the
/// right `updateItem` path (Collection-scoped or Type-root). These tests prove a
/// real round-trip: apply an edit, reload from disk via a fresh manager, assert
/// the change survived. Setup mirrors `ItemRefTests` (TempNexus + ItemTypeManager
/// + ItemContentManager(nexus:contextProvider:) + createItem), all @MainActor.
@MainActor
@Suite("CommitItemEdits")
struct CommitItemEditsTests {

    @Test("commitItemEdits persists title + description + icon for a Type-root Item")
    func commitTypeRootRoundTrip() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeManager = ItemTypeManager(nexus: nexus)
        await typeManager.loadAll()
        try await typeManager.createItemType(name: "Errands", icon: nil)
        let itemType = typeManager.types.first!

        let contentManager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        let created = try await contentManager.createItem(name: "Buy milk", inTypeRoot: itemType)

        try await contentManager.commitItemEdits(
            created,
            title: "Buy oat milk",
            icon: "cart.fill",
            description: "Pick up the carton near the eggs.",
            properties: [:],
            type: itemType,
            collection: nil
        )

        // Reload from disk via a fresh manager — proves persistence, not just
        // in-memory cache write-back.
        let fresh = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        await fresh.loadAll(for: itemType)
        let reloaded = try #require(fresh.items(in: itemType).first { $0.id == created.id })
        #expect(reloaded.title == "Buy oat milk")
        #expect(reloaded.icon == "cart.fill")
        #expect(reloaded.description == "Pick up the carton near the eggs.")
    }

    @Test("commitItemEdits persists description for a Collection-scoped Item")
    func commitCollectionRoundTrip() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeManager = ItemTypeManager(nexus: nexus)
        await typeManager.loadAll()
        try await typeManager.createItemType(name: "Errands", icon: nil)
        let itemType = typeManager.types.first!
        try await typeManager.createItemCollection(name: "Groceries", inItemType: itemType)
        let collection = typeManager.itemCollections(in: itemType).first!

        let contentManager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        let created = try await contentManager.createItem(name: "Buy milk", in: collection, type: itemType)

        try await contentManager.commitItemEdits(
            created,
            title: created.title,
            icon: "",
            description: "Whole milk, 2 cartons.",
            properties: [:],
            type: itemType,
            collection: collection
        )

        let fresh = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        await fresh.loadAll(for: collection)
        let reloaded = try #require(fresh.items(in: collection).first { $0.id == created.id })
        #expect(reloaded.description == "Whole milk, 2 cartons.")
        // Blank icon draft clears the icon to nil.
        #expect(reloaded.icon == nil)
    }

    @Test("commitItemEdits trims a whitespace-padded title and clears a blank icon")
    func commitTrimsTitleAndClearsIcon() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeManager = ItemTypeManager(nexus: nexus)
        await typeManager.loadAll()
        try await typeManager.createItemType(name: "Errands", icon: nil)
        let itemType = typeManager.types.first!

        let contentManager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        let created = try await contentManager.createItem(name: "Task", icon: "star", inTypeRoot: itemType)

        try await contentManager.commitItemEdits(
            created,
            title: "  Renamed Task  ",
            icon: "   ",
            description: "",
            properties: [:],
            type: itemType,
            collection: nil
        )

        let fresh = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        await fresh.loadAll(for: itemType)
        let reloaded = try #require(fresh.items(in: itemType).first { $0.id == created.id })
        #expect(reloaded.title == "Renamed Task")
        #expect(reloaded.icon == nil)
    }
}
