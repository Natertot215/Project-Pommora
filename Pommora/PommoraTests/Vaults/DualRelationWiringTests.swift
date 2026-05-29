import Foundation
import Testing

@testable import Pommora

/// G.5: Tests that `PageTypeManager.addProperty` and `ItemTypeManager.addProperty`
/// route paired relations through `DualRelationCoordinator` atomically.
@MainActor
@Suite("DualRelationWiring")
struct DualRelationWiringTests {

    // MARK: - PageTypeManager wiring

    @Test("addProperty with dualProperty creates both PageType sidecars atomically")
    func pageManagerAddPairedRelationWritesBothSides() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createPageType(name: "Projects", icon: nil)
        try await manager.createPageType(name: "Tasks", icon: nil)

        let projects = manager.types.first { $0.title == "Projects" }!
        let tasks = manager.types.first { $0.title == "Tasks" }!

        // Build a paired-relation definition. Convention: `syncedPropertyID` holds
        // the reverse property's desired display name at add-time.
        let def = PropertyDefinition(
            id: "",
            name: "Tasks",
            type: .relation,
            relationTarget: .pageType(tasks.id),
            dualProperty: PropertyDefinition.DualPropertyConfig(
                syncedPropertyID: "Projects",             // reverse display name (add-time convention)
                syncedPropertyDefinedOnTypeID: tasks.id   // target Type
            )
        )
        try await manager.addProperty(def, to: projects.id)

        // Both sidecars must now have a relation property.
        let reloadedProjects = manager.types.first { $0.title == "Projects" }!
        let reloadedTasks = manager.types.first { $0.title == "Tasks" }!

        let sourceProperty = reloadedProjects.properties.first { $0.type == .relation }
        let reverseProperty = reloadedTasks.properties.first { $0.type == .relation }

        #expect(sourceProperty != nil)
        #expect(reverseProperty != nil)

        // IDs must cross-reference via dualProperty.
        #expect(sourceProperty?.dualProperty?.syncedPropertyID == reverseProperty?.id)
        #expect(reverseProperty?.dualProperty?.syncedPropertyID == sourceProperty?.id)

        // Check on-disk state independently.
        let projectsMeta = NexusPaths.vaultMetadataURL(forTitle: "Projects", in: nexus)
        let tasksMeta = NexusPaths.vaultMetadataURL(forTitle: "Tasks", in: nexus)
        let diskProjects = try PageType.load(from: projectsMeta)
        let diskTasks = try PageType.load(from: tasksMeta)
        #expect(diskProjects.properties.contains { $0.type == .relation })
        #expect(diskTasks.properties.contains { $0.type == .relation })
    }

    @Test("deleteProperty with dualProperty cascades to both PageType sidecars")
    func pageManagerDeletePairedRelationCascades() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createPageType(name: "Projects", icon: nil)
        try await manager.createPageType(name: "Tasks", icon: nil)

        let projects = manager.types.first { $0.title == "Projects" }!
        let tasks = manager.types.first { $0.title == "Tasks" }!

        let def = PropertyDefinition(
            id: "",
            name: "Tasks",
            type: .relation,
            relationTarget: .pageType(tasks.id),
            dualProperty: PropertyDefinition.DualPropertyConfig(
                syncedPropertyID: "Projects",
                syncedPropertyDefinedOnTypeID: tasks.id
            )
        )
        try await manager.addProperty(def, to: projects.id)

        // Identify the minted source property ID.
        let sourcePropertyID = manager.types.first { $0.title == "Projects" }!
            .properties.first { $0.type == .relation }!.id

        // Delete the source side — should cascade to the reverse.
        try await manager.deleteProperty(id: sourcePropertyID, in: projects.id)

        let finalProjects = manager.types.first { $0.title == "Projects" }!
        let finalTasks = manager.types.first { $0.title == "Tasks" }!

        #expect(finalProjects.properties.contains { $0.type == .relation } == false)
        #expect(finalTasks.properties.contains { $0.type == .relation } == false)
    }

    // MARK: - ItemTypeManager wiring

    @Test("ItemTypeManager.addProperty with dualProperty creates both ItemType sidecars atomically")
    func itemManagerAddPairedRelationWritesBothSides() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Books", icon: nil)
        try await manager.createItemType(name: "Authors", icon: nil)

        let books = manager.types.first { $0.title == "Books" }!
        let authors = manager.types.first { $0.title == "Authors" }!

        let def = PropertyDefinition(
            id: "",
            name: "Authors",
            type: .relation,
            relationTarget: .itemType(authors.id),
            dualProperty: PropertyDefinition.DualPropertyConfig(
                syncedPropertyID: "Books",
                syncedPropertyDefinedOnTypeID: authors.id
            )
        )
        try await manager.addProperty(def, to: books.id)

        let reloadedBooks = manager.types.first { $0.title == "Books" }!
        let reloadedAuthors = manager.types.first { $0.title == "Authors" }!

        let sourceProperty = reloadedBooks.properties.first { $0.type == .relation }
        let reverseProperty = reloadedAuthors.properties.first { $0.type == .relation }

        #expect(sourceProperty != nil)
        #expect(reverseProperty != nil)
        #expect(sourceProperty?.dualProperty?.syncedPropertyID == reverseProperty?.id)
        #expect(reverseProperty?.dualProperty?.syncedPropertyID == sourceProperty?.id)
    }

    @Test("ItemTypeManager.deleteProperty with dualProperty cascades to both ItemType sidecars")
    func itemManagerDeletePairedRelationCascades() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Books", icon: nil)
        try await manager.createItemType(name: "Authors", icon: nil)

        let books = manager.types.first { $0.title == "Books" }!
        let authors = manager.types.first { $0.title == "Authors" }!

        let def = PropertyDefinition(
            id: "",
            name: "Authors",
            type: .relation,
            relationTarget: .itemType(authors.id),
            dualProperty: PropertyDefinition.DualPropertyConfig(
                syncedPropertyID: "Books",
                syncedPropertyDefinedOnTypeID: authors.id
            )
        )
        try await manager.addProperty(def, to: books.id)

        let sourcePropertyID = manager.types.first { $0.title == "Books" }!
            .properties.first { $0.type == .relation }!.id

        try await manager.deleteProperty(id: sourcePropertyID, in: books.id)

        let finalBooks = manager.types.first { $0.title == "Books" }!
        let finalAuthors = manager.types.first { $0.title == "Authors" }!

        #expect(finalBooks.properties.contains { $0.type == .relation } == false)
        #expect(finalAuthors.properties.contains { $0.type == .relation } == false)
    }
}
