import Foundation
import Testing

@testable import Pommora

/// Covers `ItemRef` (T4.1) — the Codable+Hashable scene identifier for the
/// floating Item Window, plus its `resolve(...)` against live managers.
@MainActor
@Suite("ItemRef")
struct ItemRefTests {

    // MARK: - Codable + Hashable

    @Test("ItemRef round-trips through JSON")
    func codableRoundTrip() throws {
        let ref = ItemRef(itemID: "I1", typeID: "T1", collectionID: "C1")
        let data = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(ItemRef.self, from: data)
        #expect(decoded == ref)

        // nil collectionID (type-root Item) round-trips too.
        let rootRef = ItemRef(itemID: "I2", typeID: "T2", collectionID: nil)
        let rootData = try JSONEncoder().encode(rootRef)
        let rootDecoded = try JSONDecoder().decode(ItemRef.self, from: rootData)
        #expect(rootDecoded == rootRef)
        #expect(rootDecoded.collectionID == nil)
    }

    @Test("Equal ItemRefs hash equal")
    func hashableEquality() {
        let a = ItemRef(itemID: "I1", typeID: "T1", collectionID: "C1")
        let b = ItemRef(itemID: "I1", typeID: "T1", collectionID: "C1")
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)

        var set: Set<ItemRef> = [a]
        #expect(set.contains(b))
        set.insert(b)
        #expect(set.count == 1)
    }

    // MARK: - resolve

    @Test("resolve returns the live (item, type, collection) triple")
    func resolveCollectionItem() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeManager = ItemTypeManager(nexus: nexus)
        await typeManager.loadAll()
        try await typeManager.createItemType(name: "Errands", icon: nil)
        let itemType = typeManager.types.first!
        try await typeManager.createItemCollection(name: "Groceries", inItemType: itemType)
        let collection = typeManager.itemCollections(in: itemType).first!

        let contentManager = ItemContentManager(
            nexus: nexus, contextProvider: { NexusContext.empty })
        let created = try await contentManager.createItem(
            name: "Buy milk", in: collection, type: itemType)

        let ref = ItemRef(
            itemID: created.id, typeID: itemType.id, collectionID: collection.id)
        let resolved = ref.resolve(
            itemTypeManager: typeManager, itemContentManager: contentManager)

        let triple = try #require(resolved)
        #expect(triple.0.id == created.id)
        #expect(triple.0.title == "Buy milk")
        #expect(triple.1.id == itemType.id)
        #expect(triple.2?.id == collection.id)
    }

    @Test("resolve returns the type-root Item when collectionID is nil")
    func resolveTypeRootItem() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeManager = ItemTypeManager(nexus: nexus)
        await typeManager.loadAll()
        try await typeManager.createItemType(name: "Notes", icon: nil)
        let itemType = typeManager.types.first!

        let contentManager = ItemContentManager(
            nexus: nexus, contextProvider: { NexusContext.empty })
        let created = try await contentManager.createItem(
            name: "Idea", inTypeRoot: itemType)

        let ref = ItemRef(itemID: created.id, typeID: itemType.id, collectionID: nil)
        let resolved = ref.resolve(
            itemTypeManager: typeManager, itemContentManager: contentManager)

        let triple = try #require(resolved)
        #expect(triple.0.id == created.id)
        #expect(triple.1.id == itemType.id)
        #expect(triple.2 == nil)
    }

    @Test("resolve returns nil for an unknown itemID")
    func resolveUnknownItemIsNil() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeManager = ItemTypeManager(nexus: nexus)
        await typeManager.loadAll()
        try await typeManager.createItemType(name: "Errands", icon: nil)
        let itemType = typeManager.types.first!
        try await typeManager.createItemCollection(name: "Groceries", inItemType: itemType)
        let collection = typeManager.itemCollections(in: itemType).first!

        let contentManager = ItemContentManager(
            nexus: nexus, contextProvider: { NexusContext.empty })

        let ref = ItemRef(
            itemID: "nonexistent", typeID: itemType.id, collectionID: collection.id)
        #expect(
            ref.resolve(itemTypeManager: typeManager, itemContentManager: contentManager)
                == nil)
    }

    @Test("resolve returns nil for an unknown typeID")
    func resolveUnknownTypeIsNil() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeManager = ItemTypeManager(nexus: nexus)
        await typeManager.loadAll()
        let contentManager = ItemContentManager(
            nexus: nexus, contextProvider: { NexusContext.empty })

        let ref = ItemRef(itemID: "I1", typeID: "missing", collectionID: nil)
        #expect(
            ref.resolve(itemTypeManager: typeManager, itemContentManager: contentManager)
                == nil)
    }
}
