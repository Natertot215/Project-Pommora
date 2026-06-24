import Foundation
import Testing

@testable import Pommora

/// Verifies that committing a `.relation(...)` value through the content
/// managers routes through the Phase 6.5 tier-value adapter: TIER property
/// IDs land at the entity ROOT (`tier1/2/3`), USER relation IDs land in
/// `properties`, and empties behave per-adapter (tier → `[]` at root; user →
/// key omitted). This is the load-bearing correctness for 16a tier columns —
/// the adapter round-trips are unit-tested in `TierValueAdapterTests`; this
/// suite proves the manager write path actually invokes the adapter and the
/// result PERSISTS to disk.
///
/// Quirk #18: struct name matches the filename so `-only-testing` filters hit.
@MainActor
@Suite("RelationCommitRouting")
struct RelationCommitRoutingTests {

    // MARK: - Pages

    @Test("page: commit .relation([id]) for a tier id writes ROOT tier1, not properties")
    func pageTierRelationRoutesToRoot() async throws {
        let (nexus, collection, manager) = try await setupPageCollectionRoot()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "P", inCollectionRoot: collection)
        let page = manager.pages(in: collection).first!

        try await manager.updatePageProperty(
            page,
            propertyID: ReservedPropertyID.tier1,
            newValue: .relation(["01TARGET"]),
            pageCollection: collection,
            collection: nil
        )

        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.frontmatter.tier1 == ["01TARGET"])
        #expect(reloaded.frontmatter.properties[ReservedPropertyID.tier1] == nil)
    }

    @Test("page: commit .relation([id]) for a user relation id stores it in properties")
    func pageUserRelationRoutesToProperties() async throws {
        let (nexus, collection, manager) = try await setupPageCollectionRoot()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "P", inCollectionRoot: collection)
        let page = manager.pages(in: collection).first!
        let propID = ReservedPropertyID.mintUserPropertyID()

        try await manager.updatePageProperty(
            page,
            propertyID: propID,
            newValue: .relation(["01TARGET"]),
            pageCollection: collection,
            collection: nil
        )

        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.frontmatter.relationIDs(forPropertyID: propID) == ["01TARGET"])
        #expect(reloaded.frontmatter.properties[propID] == .relation(["01TARGET"]))
        #expect(reloaded.frontmatter.tier1 == [])
    }

    @Test("page: commit .relation([]) for a tier clears root tier1 to []")
    func pageEmptyTierRelationClearsRoot() async throws {
        let (nexus, collection, manager) = try await setupPageCollectionRoot()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "P", inCollectionRoot: collection)
        let page = manager.pages(in: collection).first!

        // Seed a non-empty tier first, then clear it via an empty .relation.
        try await manager.updatePageProperty(
            page,
            propertyID: ReservedPropertyID.tier1,
            newValue: .relation(["01TARGET"]),
            pageCollection: collection,
            collection: nil
        )
        let seeded = manager.pages(in: collection).first!
        try await manager.updatePageProperty(
            seeded,
            propertyID: ReservedPropertyID.tier1,
            newValue: .relation([]),
            pageCollection: collection,
            collection: nil
        )

        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.frontmatter.tier1 == [])
        #expect(reloaded.frontmatter.properties[ReservedPropertyID.tier1] == nil)
    }

    @Test("page: commit .relation([]) for a user relation omits the key")
    func pageEmptyUserRelationOmitsKey() async throws {
        let (nexus, collection, manager) = try await setupPageCollectionRoot()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "P", inCollectionRoot: collection)
        let page = manager.pages(in: collection).first!
        let propID = ReservedPropertyID.mintUserPropertyID()

        try await manager.updatePageProperty(
            page,
            propertyID: propID,
            newValue: .relation(["01TARGET"]),
            pageCollection: collection,
            collection: nil
        )
        let seeded = manager.pages(in: collection).first!
        try await manager.updatePageProperty(
            seeded,
            propertyID: propID,
            newValue: .relation([]),
            pageCollection: collection,
            collection: nil
        )

        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.frontmatter.properties[propID] == nil)
        #expect(reloaded.frontmatter.relationIDs(forPropertyID: propID) == [])
    }

    // MARK: - Harness

    /// Page-Type-root harness — mirrors PageContentManagerUpdatePageTests.setup
    /// (collection-root variant; no collection materialized).
    private func setupPageCollectionRoot() async throws -> (Nexus, PageCollection, PageContentManager) {
        let nexus = try TempNexus.make()
        let collection = PageCollection(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        let collectionFolder = NexusPaths.collectionFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: collectionFolder, withIntermediateDirectories: true)
        try collection.save(to: NexusPaths.collectionMetadataURL(forTitle: "V", in: nexus))

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, collection, manager)
    }

}
