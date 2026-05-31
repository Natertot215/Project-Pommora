import Foundation
import Testing

@testable import Pommora

/// Characterization tests pinning `ItemTypeManager.parentItemType(for:)` behavior
/// BEFORE the dictionary-backed lookup is replaced with a linear scan.
/// All three tests must pass against the current (dictionary-backed) implementation.
@MainActor
@Suite("ParentItemTypeLookup")
struct ParentItemTypeLookup {

    // MARK: - Test 1: Known collection resolves to its parent

    @Test("resolvesParentForKnownCollection — returns type whose id matches collection.typeID")
    func resolvesParentForKnownCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Errands", icon: nil)
        let itemType = manager.types.first!
        try await manager.createItemCollection(name: "Groceries", inItemType: itemType)

        let collection = manager.itemCollections(in: itemType).first!

        let parent = manager.parentItemType(for: collection)
        #expect(parent?.id == itemType.id)
    }

    // MARK: - Test 2: Unknown typeID returns nil

    @Test("returnsNilForUnknownTypeID — phantom typeID not in loaded types yields nil")
    func returnsNilForUnknownTypeID() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        // Build a bare ItemCollection whose typeID does not correspond to any
        // loaded ItemType — no disk write needed, parentItemType queries memory only.
        let phantomCollection = ItemCollection(
            id: ULID.generate(),
            typeID: ULID.generate(),  // deliberate mismatch — no type carries this id
            title: "Ghost Set",
            folderURL: nexus.rootURL.appendingPathComponent("Ghost Set", isDirectory: true),
            modifiedAt: Date()
        )

        let parent = manager.parentItemType(for: phantomCollection)
        #expect(parent == nil)
    }

    // MARK: - Test 3: Lookup reflects fresh state after mutation

    @Test("reflectsFreshTypeAfterMutation — result contains newly-added property")
    func reflectsFreshTypeAfterMutation() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Tasks", icon: nil)
        let itemType = manager.types.first!
        try await manager.createItemCollection(name: "Work", inItemType: itemType)

        let collection = manager.itemCollections(in: itemType).first!

        // Precondition: no properties yet.
        let before = manager.parentItemType(for: collection)
        #expect(before?.properties.isEmpty == true)

        // Mutate: add a property to the type (uses the real addProperty path,
        // mirrored from ItemTypeManagerSchemaCRUDTests.makeNumberProp).
        let def = PropertyDefinition(
            id: ReservedPropertyID.mintUserPropertyID(), name: "Priority", type: .number
        )
        try await manager.addProperty(def, to: itemType.id)

        // Lookup must return the fresh type containing the new property.
        let after = manager.parentItemType(for: collection)
        #expect(after?.properties.count == 1)
        #expect(after?.properties.first?.name == "Priority")
    }
}
