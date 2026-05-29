import Foundation
import Testing

@testable import Pommora

/// Cross-Type and between-Collection move tests for ItemContentManager (Phase H.2).
///
/// Parallel to MovePageTests — same 4 scenarios on the Items side.
@MainActor
@Suite("Move Item")
struct MoveItemTests {

    // MARK: - H.2.1: Same-Type move preserves all properties

    @Test func moveBetweenCollectionsPreservesAllProperties() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let propA = PropertyDefinition(id: "prop_aaa", name: "Priority", type: .select)
        let propB = PropertyDefinition(id: "prop_bbb", name: "Status", type: .status)
        let propC = PropertyDefinition(id: "prop_ccc", name: "Due", type: .date)
        let itemType = try makeItemType(
            nexus: nexus, title: "Tasks",
            properties: [propA, propB, propC]
        )

        let collA = try makeItemCollection(nexus: nexus, title: "CollA", in: itemType)
        let collB = try makeItemCollection(nexus: nexus, title: "CollB", in: itemType)

        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })

        let itemID = ULID.generate()
        let item = Item(
            id: itemID, title: "MyItem", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [
                "prop_aaa": .select("high"),
                "prop_bbb": .status("in_progress"),
                "prop_ccc": .date(Date(timeIntervalSince1970: 1_000_000)),
            ],
            createdAt: Date(), modifiedAt: Date()
        )
        let srcURL = NexusPaths.itemFileURL(forTitle: "MyItem", in: collA.folderURL)
        try item.save(to: srcURL)

        manager.itemsByCollection[collA.id] = [item]
        manager.itemsByCollection[collB.id] = []

        try await manager.moveItemBetweenCollections(item, from: collA, to: collB, in: itemType)

        #expect(!FileManager.default.fileExists(atPath: srcURL.path))
        let dstURL = NexusPaths.itemFileURL(forTitle: "MyItem", in: collB.folderURL)
        #expect(FileManager.default.fileExists(atPath: dstURL.path))

        let loaded = try Item.load(from: dstURL)
        #expect(loaded.properties["prop_aaa"] == .select("high"))
        #expect(loaded.properties["prop_bbb"] == .status("in_progress"))
        #expect(loaded.properties["prop_ccc"] != nil)

        #expect(manager.itemsByCollection[collA.id]?.isEmpty == true)
        #expect(manager.itemsByCollection[collB.id]?.count == 1)
    }

    // MARK: - H.2.2: Cross-Type move strips non-shared properties

    @Test func moveAcrossTypesStripsNonShared() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let p1 = PropertyDefinition(id: "prop_001", name: "Priority", type: .select)
        let p2 = PropertyDefinition(id: "prop_002", name: "Status", type: .status)
        let p3 = PropertyDefinition(id: "prop_003", name: "Due", type: .date)
        let p4 = PropertyDefinition(id: "prop_004", name: "Owner", type: .select)

        let typeA = try makeItemType(nexus: nexus, title: "TypeA", properties: [p1, p2, p3])
        let typeB = try makeItemType(nexus: nexus, title: "TypeB", properties: [p1, p4])

        let itemID = ULID.generate()
        let srcFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "TypeA")
        let item = Item(
            id: itemID, title: "Doc", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [
                "prop_001": .select("high"),   // P1 — shared: KEEP
                "prop_002": .status("done"),   // P2 — TypeA only: STRIP
                "prop_003": .date(Date()),     // P3 — TypeA only: STRIP
            ],
            createdAt: Date(), modifiedAt: Date()
        )
        let srcURL = NexusPaths.itemFileURL(forTitle: "Doc", in: srcFolder)
        try item.save(to: srcURL)

        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.itemsByTypeRoot[typeA.id] = [item]
        manager.itemsByTypeRoot[typeB.id] = []

        try await manager.moveItemAcrossTypes(
            item,
            from: typeA, fromCollection: nil,
            to: typeB, toCollection: nil
        )

        #expect(!FileManager.default.fileExists(atPath: srcURL.path))
        let dstFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "TypeB")
        let dstURL = NexusPaths.itemFileURL(forTitle: "Doc", in: dstFolder)
        #expect(FileManager.default.fileExists(atPath: dstURL.path))

        let loaded = try Item.load(from: dstURL)
        #expect(loaded.properties["prop_001"] == .select("high"))
        #expect(loaded.properties["prop_002"] == nil)
        #expect(loaded.properties["prop_003"] == nil)
        #expect(loaded.properties["prop_004"] == nil)

        #expect(manager.itemsByTypeRoot[typeA.id]?.isEmpty == true)
        #expect(manager.itemsByTypeRoot[typeB.id]?.count == 1)
    }

    // MARK: - H.2.3: Cross-Type move clears paired-relation back-refs

    @Test func moveAcrossTypesClearsPairedRelationBackRefs() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // TypeProjects has "Tasks" reverse relation.
        let revProp = PropertyDefinition(
            id: "prop_rev",
            name: "Tasks",
            type: .relation,
            dualProperty: nil
        )
        let typeProjects = try makeItemType(nexus: nexus, title: "Projects", properties: [revProp])

        // TypeA has "Project" relation pointing to typeProjects with dual config.
        let relProp = PropertyDefinition(
            id: "prop_rel",
            name: "Project",
            type: .relation,
            dualProperty: PropertyDefinition.DualPropertyConfig(
                syncedPropertyID: "prop_rev",
                syncedPropertyDefinedOnTypeID: typeProjects.id
            )
        )
        // TypeB does not have "Project" → it will be stripped.
        let typeA = try makeItemType(nexus: nexus, title: "TypeA", properties: [relProp])
        let typeB = try makeItemType(nexus: nexus, title: "TypeB", properties: [])

        // Item Y lives in TypeProjects and has item X in its "Tasks" reverse.
        let itemXID = ULID.generate()
        let itemYID = ULID.generate()

        let projectsFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "Projects")
        let itemY = Item(
            id: itemYID, title: "ProjectY", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: ["prop_rev": .relation([itemXID])],
            createdAt: Date(), modifiedAt: Date()
        )
        let yURL = NexusPaths.itemFileURL(forTitle: "ProjectY", in: projectsFolder)
        try itemY.save(to: yURL)

        // Item X lives in TypeA and points to Y.
        let typeAFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "TypeA")
        let itemX = Item(
            id: itemXID, title: "TaskX", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: ["prop_rel": .relation([itemYID])],
            createdAt: Date(), modifiedAt: Date()
        )
        let xURL = NexusPaths.itemFileURL(forTitle: "TaskX", in: typeAFolder)
        try itemX.save(to: xURL)

        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.itemsByTypeRoot[typeA.id] = [itemX]
        manager.itemsByTypeRoot[typeB.id] = []

        try await manager.moveItemAcrossTypes(
            itemX,
            from: typeA, fromCollection: nil,
            to: typeB, toCollection: nil
        )

        // Item Y's "Tasks" back-ref to X should be cleared.
        let loadedY = try Item.load(from: yURL)
        let revVal = loadedY.properties["prop_rev"]
        let backRefCleared =
            revVal == nil
            || revVal == .null
            || revVal == .relation([])
        #expect(backRefCleared)
    }

    // MARK: - H.2.4: Rollback on transaction failure

    @Test func rollbackRestoresItemAndTargetSideOnFailure() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let p1 = PropertyDefinition(id: "prop_x1", name: "Tag", type: .select)
        let typeA = try makeItemType(nexus: nexus, title: "SourceType", properties: [p1])
        // Destination type with a non-existent folder → write will fail.
        let typeB = ItemType(
            id: ULID.generate(), title: "MissingType", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )

        let itemID = ULID.generate()
        let srcFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "SourceType")
        let item = Item(
            id: itemID, title: "ItemX", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: ["prop_x1": .select("active")],
            createdAt: Date(), modifiedAt: Date()
        )
        let srcURL = NexusPaths.itemFileURL(forTitle: "ItemX", in: srcFolder)
        try item.save(to: srcURL)

        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.itemsByTypeRoot[typeA.id] = [item]

        var threw = false
        do {
            try await manager.moveItemAcrossTypes(
                item,
                from: typeA, fromCollection: nil,
                to: typeB, toCollection: nil
            )
        } catch {
            threw = true
        }
        #expect(threw)

        // Source file must still be intact.
        #expect(FileManager.default.fileExists(atPath: srcURL.path))
        let loadedBack = try Item.load(from: srcURL)
        #expect(loadedBack.id == itemID)
        #expect(loadedBack.properties["prop_x1"] == .select("active"))
    }

    // MARK: - Private setup helpers

    @discardableResult
    private func makeItemType(
        nexus: Nexus,
        title: String,
        properties: [PropertyDefinition]
    ) throws -> ItemType {
        let itemType = ItemType(
            id: ULID.generate(), title: title, icon: nil,
            properties: properties, views: [], modifiedAt: Date()
        )
        let folderURL = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: title)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try itemType.save(to: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: title))
        return itemType
    }

    @discardableResult
    private func makeItemCollection(
        nexus: Nexus,
        title: String,
        in itemType: ItemType
    ) throws -> ItemCollection {
        let folderURL = NexusPaths.itemCollectionFolderURL(
            in: nexus.rootURL,
            typeFolderName: itemType.title,
            collectionFolderName: title
        )
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let coll = ItemCollection(
            id: ULID.generate(),
            typeID: itemType.id,
            title: title,
            folderURL: folderURL,
            modifiedAt: Date()
        )
        try coll.save(to: folderURL.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename))
        return coll
    }
}
