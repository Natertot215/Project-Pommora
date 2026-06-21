import Foundation
import Testing

@testable import Pommora

/// Test-only unification of the three free-standing Context managers (Area /
/// Topic / Project) over their identical CRUD surface, so the shared create /
/// rename / delete / duplicate-title assertions live once. Production managers
/// stay separate — this protocol and its conformances are test-target only.
@MainActor
protocol TestableContextManager: AnyObject {
    associatedtype Entity: TitledContextEntity
    var testItems: [Entity] { get }
    func loadAll() async
    @discardableResult func create(name: String, icon: String?) async throws -> Entity
    func rename(_ entity: Entity, to newName: String) async throws
    func delete(_ entity: Entity) async throws
}

@MainActor
protocol TitledContextEntity {
    var title: String { get }
}

extension Area: TitledContextEntity {}
extension Topic: TitledContextEntity {}
extension Project: TitledContextEntity {}

extension AreaManager: TestableContextManager {
    var testItems: [Area] { areas }
}
extension TopicManager: TestableContextManager {
    var testItems: [Topic] { topics }
}
extension ProjectManager: TestableContextManager {
    var testItems: [Project] { projects }
}

/// Shared CRUD assertions for the Context managers. Each takes the manager-
/// specific `NexusPaths` URL function so the on-disk checks stay typed.
@MainActor
enum ContextCRUDChecks {

    static func assertCreate<M: TestableContextManager>(
        _ manager: M, in nexus: Nexus, named name: String,
        metadataURL: (String, Nexus) -> URL
    ) async throws {
        await manager.loadAll()
        try await manager.create(name: name, icon: nil)
        #expect(FileManager.default.fileExists(atPath: metadataURL(name, nexus).path))
        #expect(manager.testItems.count == 1)
        #expect(manager.testItems.first?.title == name)
    }

    static func assertDuplicateThrows<M: TestableContextManager, E: Error & Equatable>(
        _ manager: M, named name: String, caseVariant duplicate: String, throwing error: E
    ) async throws {
        await manager.loadAll()
        try await manager.create(name: name, icon: nil)
        await #expect(throws: error) {
            _ = try await manager.create(name: duplicate, icon: nil)
        }
        #expect(manager.testItems.count == 1)
    }

    static func assertRename<M: TestableContextManager>(
        _ manager: M, in nexus: Nexus, from oldName: String, to newName: String,
        folderURL: (String, Nexus) -> URL
    ) async throws {
        await manager.loadAll()
        let entity = try await manager.create(name: oldName, icon: nil)
        try await manager.rename(entity, to: newName)
        #expect(!FileManager.default.fileExists(atPath: folderURL(oldName, nexus).path))
        #expect(FileManager.default.fileExists(atPath: folderURL(newName, nexus).path))
        #expect(manager.testItems.first?.title == newName)
    }

    static func assertDelete<M: TestableContextManager>(
        _ manager: M, in nexus: Nexus, named name: String,
        folderURL: (String, Nexus) -> URL
    ) async throws {
        await manager.loadAll()
        let entity = try await manager.create(name: name, icon: nil)
        try await manager.delete(entity)
        #expect(!FileManager.default.fileExists(atPath: folderURL(name, nexus).path))
        #expect(manager.testItems.isEmpty)
    }
}
