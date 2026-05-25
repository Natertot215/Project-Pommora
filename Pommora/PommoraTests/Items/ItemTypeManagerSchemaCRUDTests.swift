import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("ItemTypeManagerSchemaCRUD")
struct ItemTypeManagerSchemaCRUDTests {

    // MARK: - Helper

    /// Builds a minimal PropertyDefinition fixture with a minted ID.
    private func makeNumberProp(name: String = "Score") -> PropertyDefinition {
        PropertyDefinition(id: ReservedPropertyID.mintUserPropertyID(), name: name, type: .number)
    }

    // MARK: - Test 1: addProperty mints ID and persists

    @Test("addProperty with empty id mints prop_ ID and persists to sidecar")
    func addPropertyMintsIDAndPersists() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Tasks", icon: nil)
        let itemType = manager.types.first!

        // Pass id: "" — addProperty should mint a new ID.
        let def = PropertyDefinition(id: "", name: "Priority", type: .number)
        try await manager.addProperty(def, to: itemType.id)

        // In-memory: exactly one property with correct name.
        let updated = manager.types.first { $0.id == itemType.id }!
        #expect(updated.properties.count == 1)
        let stored = updated.properties[0]
        #expect(stored.name == "Priority")
        #expect(stored.id.hasPrefix("prop_"))

        // On-disk: reload sidecar and verify.
        let meta = NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "Tasks")
        let reloaded = try ItemType.load(from: meta)
        #expect(reloaded.properties.count == 1)
        #expect(reloaded.properties[0].name == "Priority")
        #expect(reloaded.properties[0].id.hasPrefix("prop_"))
    }

    // MARK: - Test 2: rename does not rewrite member files

    @Test("renameProperty updates schema only — member files are untouched")
    func renameDoesNotRewriteMemberFiles() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Tasks", icon: nil)
        let itemType = manager.types.first!

        let prop = makeNumberProp(name: "Score")
        try await manager.addProperty(prop, to: itemType.id)
        let storedPropID = manager.types.first { $0.id == itemType.id }!.properties[0].id

        // Write a fake Item .json file into the ItemType folder referencing the property.
        let itemTypeFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "Tasks")
        let itemFile = itemTypeFolder.appendingPathComponent("Item1.json")
        let now = Date()
        let item = Item(
            id: ULID.generate(),
            title: "Item1",
            icon: nil,
            description: "",
            tier1: [],
            tier2: [],
            tier3: [],
            properties: [storedPropID: .number(42)],
            createdAt: now,
            modifiedAt: now
        )
        try AtomicJSON.write(item, to: itemFile)

        // Capture file data before rename.
        let dataBefore = try Data(contentsOf: itemFile)

        // Rename the property (schema-only).
        try await manager.renameProperty(id: storedPropID, in: itemType.id, to: "Rating")

        // Member file must be byte-identical.
        let dataAfter = try Data(contentsOf: itemFile)
        #expect(dataBefore == dataAfter)

        // Schema in-memory and on-disk must reflect new name.
        let updatedType = manager.types.first { $0.id == itemType.id }!
        #expect(updatedType.properties[0].name == "Rating")
        let meta = NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "Tasks")
        let reloaded = try ItemType.load(from: meta)
        #expect(reloaded.properties[0].name == "Rating")
    }

    // MARK: - Test 3: changeType same type is lossless (no confirmation needed)

    @Test("changeType same type is treated as lossless — no throw")
    func changeTypeSameTypeNoOpIsLossless() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Tracker", icon: nil)
        let itemType = manager.types.first!

        let prop = makeNumberProp()
        try await manager.addProperty(prop, to: itemType.id)
        let storedPropID = manager.types.first { $0.id == itemType.id }!.properties[0].id

        // number → number: should succeed without dropConflictingValues.
        try await manager.changeType(
            of: storedPropID, in: itemType.id, to: .number, dropConflictingValues: false
        )

        let updatedType = manager.types.first { $0.id == itemType.id }!
        #expect(updatedType.properties[0].type == .number)
    }

    // MARK: - Test 4: changeType lossy with dropConflictingValues strips member-file values

    @Test("changeType lossy with dropConflictingValues=true removes value from member files")
    func changeTypeLossyDropsValuesViaSchemaTransaction() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Tracker", icon: nil)
        let itemType = manager.types.first!

        let prop = makeNumberProp(name: "Score")
        try await manager.addProperty(prop, to: itemType.id)
        let storedPropID = manager.types.first { $0.id == itemType.id }!.properties[0].id

        // Write a fake Item .json file with a numeric value for the property.
        let itemTypeFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "Tracker")
        let itemFile = itemTypeFolder.appendingPathComponent("Entry1.json")
        let now = Date()
        let item = Item(
            id: ULID.generate(),
            title: "Entry1",
            icon: nil,
            description: "",
            tier1: [],
            tier2: [],
            tier3: [],
            properties: [storedPropID: .number(99)],
            createdAt: now,
            modifiedAt: now
        )
        try AtomicJSON.write(item, to: itemFile)

        // Change number → checkbox, with value drop.
        try await manager.changeType(
            of: storedPropID, in: itemType.id, to: .checkbox, dropConflictingValues: true
        )

        // Schema: property type updated.
        let updatedType = manager.types.first { $0.id == itemType.id }!
        #expect(updatedType.properties[0].type == .checkbox)

        // Member file: property key must be GONE.
        let reloadedItem = try Item.load(from: itemFile)
        #expect(reloadedItem.properties[storedPropID] == nil)
    }

    // MARK: - Test 5: changeType lossy without confirmation throws

    @Test("changeType lossy without dropConflictingValues throws lossyChangeRequiresConfirmation")
    func changeTypeLossyWithoutConfirmThrows() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Tracker", icon: nil)
        let itemType = manager.types.first!

        let prop = makeNumberProp(name: "Score")
        try await manager.addProperty(prop, to: itemType.id)
        let storedPropID = manager.types.first { $0.id == itemType.id }!.properties[0].id

        // number → checkbox without dropConflictingValues should throw.
        await #expect(throws: ItemTypeManagerError.lossyChangeRequiresConfirmation) {
            try await manager.changeType(
                of: storedPropID, in: itemType.id, to: .checkbox, dropConflictingValues: false
            )
        }
    }
}
