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
/// Identity check across all entity types: the returned entity must match
/// the entity recorded in the manager's in-memory state by `.id`. (Title
/// comparison is incidental; identity is the durable contract.)
@MainActor
@Suite("Manager create return contract")
struct ManagerCreateReturnContractTests {

    @Test("PageCollectionManager.createPageCollection returns the new PageCollection")
    func createPageCollectionReturns() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageCollectionManager(nexus: nexus)
        await manager.loadAll()

        let returned = try await manager.createPageCollection(name: "Planner", icon: nil)
        #expect(manager.types.contains(where: { $0.id == returned.id }))
        #expect(returned.title == "Planner")
    }

    @Test("PageCollectionManager.createPageSet returns the new PageSet")
    func createPageSetReturns() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageCollectionManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageCollectionProvider = { [weak manager] in manager?.types ?? [] }
        manager.pageSetManager = setManager
        await manager.loadAll()
        let pt = try await manager.createPageCollection(name: "Planner", icon: nil)

        let returned = try await manager.createPageCollection(name: "Tasks", inPageCollection: pt)
        #expect(manager.pageCollections(in: pt).contains(where: { $0.id == returned.id }))
        #expect(returned.title == "Tasks")
        #expect(returned.parentID == pt.id)
    }

    @Test("AreaManager.create returns the new Area")
    func createAreaReturns() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AreaManager(nexus: nexus)
        await manager.loadAll()

        let returned = try await manager.create(name: "Personal", icon: nil)
        #expect(manager.areas.contains(where: { $0.id == returned.id }))
        #expect(returned.title == "Personal")
    }

    @Test("TopicManager.createTopic returns the new Topic")
    func createTopicReturns() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = TopicManager(nexus: nexus)
        await manager.loadAll()

        let returned = try await manager.create(name: "Productivity", icon: nil)
        #expect(manager.topics.contains(where: { $0.id == returned.id }))
        #expect(returned.title == "Productivity")
    }

    @Test("ProjectManager.create returns the new Project")
    func createProjectReturns() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ProjectManager(nexus: nexus)
        await manager.loadAll()

        let returned = try await manager.create(name: "GTD", icon: nil)
        #expect(manager.projects.contains(where: { $0.id == returned.id }))
        #expect(returned.title == "GTD")
    }
}
