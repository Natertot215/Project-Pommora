import Foundation
import Testing

@testable import Pommora

/// Phase 6: `ItemValidator` was retyped off `PageType` onto `ItemType` and wired
/// into all six Item CRUD entry points for the FIRST time (save-time validation
/// previously had zero production callers). These cover the validator in
/// isolation, the live wiring through the manager (proving validation is not
/// dead), and the `ItemValidator.friendly(_:)` mapping.
@MainActor
@Suite("ItemValidator")
struct ItemValidatorTests {

    // MARK: - Validator unit (retyped vault: PageType → itemType: ItemType)

    @Test("happy path: valid title + resolving tier IDs + matching property values")
    func happy() throws {
        let spaceID = ULID.generate()
        let topicID = ULID.generate()
        let projectID = ULID.generate()
        let propID = "prop_status_001"
        let space = Space(
            id: spaceID, title: "S", color: .blue, icon: nil,
            blocks: [], modifiedAt: Date())
        let topic = Topic(
            id: topicID, title: "T", parents: [],
            icon: nil, blocks: [], modifiedAt: Date())
        let project = Project(
            id: projectID, title: "U", parents: ["01HX"],
            linkedRelations: [], icon: nil, blocks: [], modifiedAt: Date())
        let context = NexusContext(
            lookupSpace: { id in id == spaceID ? space : nil },
            lookupTopic: { id in id == topicID ? topic : nil },
            lookupProject: { id in id == projectID ? project : nil },
            lookupVault: { _ in nil }
        )
        let itemType = makeItemType(properties: [
            PropertyDefinition(
                id: propID, name: "status", type: .select,
                selectOptions: [PropertyDefinition.SelectOption(value: "Active", label: "Active", color: nil)])
        ])
        try ItemValidator.validate(
            title: "Buy groceries",
            tier1: [spaceID], tier2: [topicID], tier3: [projectID],
            properties: [propID: .select("Active")],
            itemType: itemType,
            context: context
        )
    }

    @Test("tier1 ID resolving to a Topic (wrong tier) throws")
    func tier1WrongTier() {
        let topicID = ULID.generate()
        let topic = Topic(
            id: topicID, title: "T", parents: [],
            icon: nil, blocks: [], modifiedAt: Date())
        let context = NexusContext(
            lookupSpace: { _ in nil },
            lookupTopic: { id in id == topicID ? topic : nil },
            lookupProject: { _ in nil },
            lookupVault: { _ in nil }
        )
        let itemType = makeItemType(properties: [])
        #expect(throws: ItemValidator.ValidationError.tierMismatch(expectedTier: 1, id: topicID)) {
            try ItemValidator.validate(
                title: "X", tier1: [topicID], tier2: [], tier3: [],
                properties: [:], itemType: itemType,
                context: context
            )
        }
    }

    @Test("property value of wrong type throws .propertyTypeMismatch(id:)")
    func wrongPropertyType() {
        let propID = "prop_count_001"
        let itemType = makeItemType(properties: [
            PropertyDefinition(id: propID, name: "count", type: .number)
        ])
        #expect(throws: ItemValidator.ValidationError.propertyTypeMismatch(id: propID)) {
            try ItemValidator.validate(
                title: "X", tier1: [], tier2: [], tier3: [],
                properties: [propID: .checkbox(true)],  // wrong type
                itemType: itemType,
                context: .empty
            )
        }
    }

    @Test("property not in itemType schema throws .unknownProperty(id:)")
    func unknownProperty() {
        let itemType = makeItemType(properties: [])
        #expect(throws: ItemValidator.ValidationError.unknownProperty(id: "phantom")) {
            try ItemValidator.validate(
                title: "X", tier1: [], tier2: [], tier3: [],
                properties: ["phantom": .select("a")],
                itemType: itemType,
                context: .empty
            )
        }
    }

    @Test("unknown property ID carries the ID in the error")
    func unknownPropertyIDThrowsWithIDInError() {
        let itemType = makeItemType(properties: [])
        #expect(throws: ItemValidator.ValidationError.unknownProperty(id: "prop_abc_999")) {
            try ItemValidator.validate(
                title: "X", tier1: [], tier2: [], tier3: [],
                properties: ["prop_abc_999": .select("a")],
                itemType: itemType,
                context: .empty
            )
        }
    }

    // MARK: - Description / body cap (Shape A: description == body)

    @Test("description body at exactly the cap (1000) passes")
    func bodyAtCapPasses() throws {
        let itemType = makeItemType(properties: [])
        let body = String(repeating: "a", count: ItemValidator.maxDescriptionLength)
        try ItemValidator.validate(
            title: "X", tier1: [], tier2: [], tier3: [],
            description: body, properties: [:],
            itemType: itemType, context: .empty
        )
    }

    @Test("description body over the cap throws .descriptionTooLong")
    func bodyOverCapThrows() {
        let itemType = makeItemType(properties: [])
        let body = String(repeating: "a", count: ItemValidator.maxDescriptionLength + 1)
        #expect(throws: ItemValidator.ValidationError.descriptionTooLong(cap: ItemValidator.maxDescriptionLength)) {
            try ItemValidator.validate(
                title: "X", tier1: [], tier2: [], tier3: [],
                description: body, properties: [:],
                itemType: itemType, context: .empty
            )
        }
    }

    // MARK: - Live wiring through the manager (proves validation is not dead)

    @Test("collection-scoped updateItem with body over the cap throws")
    func collectionUpdateOverCapThrows() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }
        let created = try await manager.createItem(name: "Item", in: coll, type: itemType)

        var updated = created
        updated.description = String(repeating: "a", count: ItemValidator.maxDescriptionLength + 1)
        await #expect(throws: ItemValidator.ValidationError.descriptionTooLong(cap: ItemValidator.maxDescriptionLength)) {
            try await manager.updateItem(updated, in: coll, type: itemType)
        }
    }

    @Test("type-root updateItem with body over the cap throws")
    func typeRootUpdateOverCapThrows() async throws {
        let (nexus, itemType, manager) = try await setupTypeRoot()
        defer { TempNexus.cleanup(nexus) }
        let created = try await manager.createItem(name: "Item", inTypeRoot: itemType)

        var updated = created
        updated.description = String(repeating: "a", count: ItemValidator.maxDescriptionLength + 1)
        await #expect(throws: ItemValidator.ValidationError.descriptionTooLong(cap: ItemValidator.maxDescriptionLength)) {
            try await manager.updateItem(updated, inTypeRoot: itemType)
        }
    }

    @Test("collection-scoped updateItem with a body at the cap succeeds")
    func collectionUpdateAtCapSucceeds() async throws {
        let (nexus, itemType, coll, manager) = try await setupCollection()
        defer { TempNexus.cleanup(nexus) }
        let created = try await manager.createItem(name: "Item", in: coll, type: itemType)

        var updated = created
        updated.description = String(repeating: "a", count: ItemValidator.maxDescriptionLength)
        try await manager.updateItem(updated, in: coll, type: itemType)

        let url = NexusPaths.itemFileURL(forTitle: "Item", in: coll.folderURL)
        let reloaded = try Item.load(from: url)
        #expect(reloaded.description.count == ItemValidator.maxDescriptionLength)
    }

    @Test("type-root updateItem with an unknown property throws (schema fires on save)")
    func typeRootUpdateUnknownPropertyThrows() async throws {
        let (nexus, itemType, manager) = try await setupTypeRoot()
        defer { TempNexus.cleanup(nexus) }
        let created = try await manager.createItem(name: "Item", inTypeRoot: itemType)

        var updated = created
        updated.properties["phantom_prop"] = .select("a")  // not in the (empty) schema
        await #expect(throws: ItemValidator.ValidationError.unknownProperty(id: "phantom_prop")) {
            try await manager.updateItem(updated, inTypeRoot: itemType)
        }
    }

    @Test("collection-scoped updateItem with a property-type mismatch throws")
    func collectionUpdateTypeMismatchThrows() async throws {
        let propID = "prop_count_001"
        let (nexus, itemType, coll, manager) = try await setupCollection(properties: [
            PropertyDefinition(id: propID, name: "count", type: .number)
        ])
        defer { TempNexus.cleanup(nexus) }
        let created = try await manager.createItem(name: "Item", in: coll, type: itemType)

        var updated = created
        updated.properties[propID] = .checkbox(true)  // schema says .number
        await #expect(throws: ItemValidator.ValidationError.propertyTypeMismatch(id: propID)) {
            try await manager.updateItem(updated, in: coll, type: itemType)
        }
    }

    @Test("type-root updateItem with an invalid tier reference throws")
    func typeRootUpdateInvalidTierThrows() async throws {
        let (nexus, itemType, manager) = try await setupTypeRoot()
        defer { TempNexus.cleanup(nexus) }
        let created = try await manager.createItem(name: "Item", inTypeRoot: itemType)
        // Manager's contextProvider is NexusContext.empty → every tier lookup fails.
        let danglingID = ULID.generate()

        var updated = created
        updated.tier1 = [danglingID]
        await #expect(throws: ItemValidator.ValidationError.tierMismatch(expectedTier: 1, id: danglingID)) {
            try await manager.updateItem(updated, inTypeRoot: itemType)
        }
    }

    // MARK: - friendly(_:) mapping (ItemValidator save-path surface)

    @Test("friendly maps every ValidationError case to a non-empty string")
    func friendlyAllCasesNonEmpty() {
        let cases: [ItemValidator.ValidationError] = [
            .emptyTitle,
            .invalidTitleCharacters,
            .descriptionTooLong(cap: 250),
            .tierMismatch(expectedTier: 1, id: "01H"),
            .unknownProperty(id: "p"),
            .propertyTypeMismatch(id: "p"),
        ]
        for error in cases {
            #expect(!ItemValidator.friendly(error).isEmpty)
        }
    }

    @Test("friendly(.descriptionTooLong) mentions source/markdown characters")
    func friendlyDescriptionMentionsSource() {
        let message = ItemValidator.friendly(.descriptionTooLong(cap: 250))
        #expect(message.contains("source/markdown characters"))
    }

    // MARK: - Fixtures

    private func makeItemType(properties: [PropertyDefinition]) -> ItemType {
        ItemType(
            id: ULID.generate(), title: "V", icon: nil,
            properties: properties, views: [], modifiedAt: Date())
    }

    /// Bootstraps a temp nexus with an ItemType + ItemCollection materialized at
    /// the Nexus root, returning a fresh manager (mirrors ItemContentManagerTests).
    private func setupCollection(
        properties: [PropertyDefinition] = []
    ) async throws -> (Nexus, ItemType, ItemCollection, ItemContentManager) {
        let nexus = try TempNexus.make()
        let itemType = ItemType(
            id: ULID.generate(), title: "T", icon: nil,
            properties: properties, views: [], modifiedAt: Date())

        let typeFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "T")
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try itemType.save(to: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "T"))

        let collFolder = NexusPaths.itemCollectionFolderURL(
            in: nexus.rootURL, typeFolderName: "T", collectionFolderName: "C"
        )
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = ItemCollection(
            id: ULID.generate(),
            typeID: itemType.id,
            title: "C",
            folderURL: collFolder,
            modifiedAt: Date()
        )
        try coll.save(to: collFolder.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename))

        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, itemType, coll, manager)
    }

    /// Type-root variant: materializes only the ItemType folder (no Collection).
    private func setupTypeRoot(
        properties: [PropertyDefinition] = []
    ) async throws -> (Nexus, ItemType, ItemContentManager) {
        let nexus = try TempNexus.make()
        let itemType = ItemType(
            id: ULID.generate(), title: "T", icon: nil,
            properties: properties, views: [], modifiedAt: Date())
        let typeFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "T")
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try itemType.save(to: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "T"))

        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, itemType, manager)
    }
}
