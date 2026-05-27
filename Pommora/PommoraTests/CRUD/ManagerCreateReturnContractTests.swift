import Foundation
import Testing

@testable import Pommora

/// Locks the F.0 contract that every entity-create manager method returns the
/// newly-created entity (instead of `Void`). The system-wide stub-and-inline-
/// rename flow needs the new entity's ID to flip the matching row's
/// `editingID` binding into rename mode immediately after the create succeeds
/// — the coordinator (`CreateWithInlineEdit.run`) reads the returned entity
/// inside `onCreate`.
///
/// Identity check across all 7 entity types: the returned entity must match
/// the entity recorded in the manager's in-memory state by `.id`. (Title
/// comparison is incidental; identity is the durable contract.)
@MainActor
@Suite("Manager create return contract")
struct ManagerCreateReturnContractTests {

    @Test("PageTypeManager.createPageType returns the new PageType")
    func createPageTypeReturns() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()

        let returned = try await manager.createPageType(name: "Planner", icon: nil)
        #expect(manager.types.contains(where: { $0.id == returned.id }))
        #expect(returned.title == "Planner")
    }

    @Test("PageTypeManager.createPageCollection returns the new PageCollection")
    func createPageCollectionReturns() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()
        let pt = try await manager.createPageType(name: "Planner", icon: nil)

        let returned = try await manager.createPageCollection(name: "Tasks", inPageType: pt)
        #expect(manager.pageCollections(in: pt).contains(where: { $0.id == returned.id }))
        #expect(returned.title == "Tasks")
        #expect(returned.typeID == pt.id)
    }

    @Test("ItemTypeManager.createItemType returns the new ItemType")
    func createItemTypeReturns() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        let returned = try await manager.createItemType(name: "Books", icon: nil)
        #expect(manager.types.contains(where: { $0.id == returned.id }))
        #expect(returned.title == "Books")
    }

    @Test("ItemTypeManager.createItemCollection returns the new ItemCollection")
    func createItemCollectionReturns() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()
        let it = try await manager.createItemType(name: "Books", icon: nil)

        let returned = try await manager.createItemCollection(name: "2026", inItemType: it)
        #expect(manager.itemCollections(in: it).contains(where: { $0.id == returned.id }))
        #expect(returned.title == "2026")
        #expect(returned.typeID == it.id)
    }

    @Test("SpaceManager.create returns the new Space")
    func createSpaceReturns() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()

        let returned = try await manager.create(name: "Personal", color: .blue, icon: nil)
        #expect(manager.spaces.contains(where: { $0.id == returned.id }))
        #expect(returned.title == "Personal")
    }

    @Test("TopicManager.createTopic returns the new Topic")
    func createTopicReturns() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = TopicManager(nexus: nexus, contextProvider: { NexusContext.empty })
        await manager.loadAll()

        let returned = try await manager.createTopic(name: "Productivity", parents: [], icon: nil)
        #expect(manager.topics.contains(where: { $0.id == returned.id }))
        #expect(returned.title == "Productivity")
    }

    @Test("TopicManager.createProject returns the new Project")
    func createProjectReturns() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = TopicManager(nexus: nexus, contextProvider: { NexusContext.empty })
        await manager.loadAll()
        let topic = try await manager.createTopic(name: "Productivity", parents: [], icon: nil)

        let returned = try await manager.createProject(name: "GTD", inTopic: topic, icon: nil)
        #expect(manager.projects(in: topic).contains(where: { $0.id == returned.id }))
        #expect(returned.title == "GTD")
    }
}
