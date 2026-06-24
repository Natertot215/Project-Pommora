import Foundation
import GRDB
import Testing

@testable import Pommora

/// Integration tests: connection-index writes stay live through
/// PageContentManager CRUD (no rebuild required).
///
/// Fixture mirrors `PageContentManagerTests.setup()` — TempNexus + one
/// PageCollection + one PageSet — and wires an `IndexUpdater` to the manager
/// so each CRUD call drives the connection index in-process.
@MainActor
@Suite("ConnectionLiveUpdateTests")
struct ConnectionLiveUpdateTests {

    // MARK: - Fixture

    private func setup() async throws -> (
        nexus: Nexus,
        pageCollection: PageCollection,
        coll: PageSet,
        manager: PageContentManager,
        index: PommoraIndex
    ) {
        let nexus = try TempNexus.make()
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let vault = PageCollection(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: "V", in: nexus))

        let collFolder = NexusPaths.collectionFolderURL(forTitle: "C", inVaultTitled: "V", in: nexus)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = PageSet(
            id: ULID.generate(),
            parentID: vault.id,
            title: "C",
            folderURL: collFolder,
            modifiedAt: Date()
        )

        // Seed the index with the vault + collection so FK constraints pass
        // when the manager calls upsertPage.
        let updater = IndexUpdater(index)
        try updater.upsertPageCollection(vault)
        try updater.upsertPageCollection(coll)

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = updater

        return (nexus, vault, coll, manager, index)
    }

    // MARK: - Test 1: live resolve on body edit

    /// updatePage body containing [[Target]] immediately resolves the edge —
    /// no rebuild required.
    @Test("reconcileConnections fires on updatePage")
    func liveResolveOnBodyEdit() async throws {
        let (nexus, vault, coll, manager, index) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        // Create Target and page A.
        let target = try await manager.createPage(name: "Target", in: coll, pageCollection: vault)
        let pageA = try await manager.createPage(name: "A", in: coll, pageCollection: vault)

        // Write a body into A that links [[Target]].
        try await manager.updatePage(pageA, body: "[[Target]]", in: coll, pageCollection: vault)

        // The connection edge from A → Target must be resolved immediately.
        let aID = pageA.id
        let targetID = target.id
        let outgoing = try await IndexQuery(index).outgoingConnections(sourceID: aID)
        #expect(outgoing.count == 1)
        let edge = try #require(outgoing.first)
        #expect(edge.resolved == true)
        #expect(edge.targetID == targetID)
        #expect(edge.targetTitle == ConnectionTitle.normalize("Target"))
    }

    // MARK: - Test 2: activate on create

    /// A phantom edge becomes resolved when its target page is created via
    /// createPage — no rebuild required.
    @Test("activateConnections fires on createPage")
    func activateOnCreate() async throws {
        let (nexus, vault, coll, manager, index) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        // Create page C and give it a body with a pending phantom link.
        let pageC = try await manager.createPage(name: "C", in: coll, pageCollection: vault)
        try await manager.updatePage(pageC, body: "[[Pending]]", in: coll, pageCollection: vault)

        // Verify the edge is phantom before the target exists.
        let cID = pageC.id
        let beforeCreate = try await IndexQuery(index).outgoingConnections(sourceID: cID)
        #expect(beforeCreate.count == 1)
        #expect(beforeCreate[0].resolved == false)
        #expect(beforeCreate[0].targetID == nil)

        // Create the target — activateConnections should flip the phantom to resolved.
        let pending = try await manager.createPage(name: "Pending", in: coll, pageCollection: vault)

        let afterCreate = try await IndexQuery(index).outgoingConnections(sourceID: cID)
        #expect(afterCreate.count == 1)
        let edge = try #require(afterCreate.first)
        #expect(edge.resolved == true)
        #expect(edge.targetID == pending.id)
    }

    // MARK: - Test 3: deactivate on delete

    /// Deleting a resolved target turns its inbound edge back to phantom.
    @Test("deactivateConnections fires on deletePage")
    func deactivateOnDelete() async throws {
        let (nexus, vault, coll, manager, index) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        // Create Target and A → Target resolved edge.
        let target = try await manager.createPage(name: "Target", in: coll, pageCollection: vault)
        let pageA = try await manager.createPage(name: "A", in: coll, pageCollection: vault)
        try await manager.updatePage(pageA, body: "[[Target]]", in: coll, pageCollection: vault)

        let aID = pageA.id
        let before = try await IndexQuery(index).outgoingConnections(sourceID: aID)
        #expect(before.first?.resolved == true)

        // Delete Target — the edge must revert to phantom.
        try await manager.deletePage(target, inCollection: coll)

        let after = try await IndexQuery(index).outgoingConnections(sourceID: aID)
        #expect(after.count == 1)
        let edge = try #require(after.first)
        #expect(edge.resolved == false)
        #expect(edge.targetID == nil)
    }
}
