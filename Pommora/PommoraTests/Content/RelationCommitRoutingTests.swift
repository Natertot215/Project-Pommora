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
        let (nexus, vault, manager) = try await setupPageTypeRoot()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "P", inVaultRoot: vault)
        let page = manager.pages(in: vault).first!

        try await manager.updatePageProperty(
            page,
            propertyID: ReservedPropertyID.tier1,
            newValue: .relation(["01TARGET"]),
            vault: vault,
            collection: nil
        )

        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.frontmatter.tier1 == ["01TARGET"])
        #expect(reloaded.frontmatter.properties[ReservedPropertyID.tier1] == nil)
    }

    @Test("page: commit .relation([id]) for a user relation id stores it in properties")
    func pageUserRelationRoutesToProperties() async throws {
        let (nexus, vault, manager) = try await setupPageTypeRoot()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "P", inVaultRoot: vault)
        let page = manager.pages(in: vault).first!
        let propID = ReservedPropertyID.mintUserPropertyID()

        try await manager.updatePageProperty(
            page,
            propertyID: propID,
            newValue: .relation(["01TARGET"]),
            vault: vault,
            collection: nil
        )

        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.frontmatter.relationIDs(forPropertyID: propID) == ["01TARGET"])
        #expect(reloaded.frontmatter.properties[propID] == .relation(["01TARGET"]))
        #expect(reloaded.frontmatter.tier1 == [])
    }

    @Test("page: commit .relation([]) for a tier clears root tier1 to []")
    func pageEmptyTierRelationClearsRoot() async throws {
        let (nexus, vault, manager) = try await setupPageTypeRoot()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "P", inVaultRoot: vault)
        let page = manager.pages(in: vault).first!

        // Seed a non-empty tier first, then clear it via an empty .relation.
        try await manager.updatePageProperty(
            page,
            propertyID: ReservedPropertyID.tier1,
            newValue: .relation(["01TARGET"]),
            vault: vault,
            collection: nil
        )
        let seeded = manager.pages(in: vault).first!
        try await manager.updatePageProperty(
            seeded,
            propertyID: ReservedPropertyID.tier1,
            newValue: .relation([]),
            vault: vault,
            collection: nil
        )

        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.frontmatter.tier1 == [])
        #expect(reloaded.frontmatter.properties[ReservedPropertyID.tier1] == nil)
    }

    @Test("page: commit .relation([]) for a user relation omits the key")
    func pageEmptyUserRelationOmitsKey() async throws {
        let (nexus, vault, manager) = try await setupPageTypeRoot()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "P", inVaultRoot: vault)
        let page = manager.pages(in: vault).first!
        let propID = ReservedPropertyID.mintUserPropertyID()

        try await manager.updatePageProperty(
            page,
            propertyID: propID,
            newValue: .relation(["01TARGET"]),
            vault: vault,
            collection: nil
        )
        let seeded = manager.pages(in: vault).first!
        try await manager.updatePageProperty(
            seeded,
            propertyID: propID,
            newValue: .relation([]),
            vault: vault,
            collection: nil
        )

        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.frontmatter.properties[propID] == nil)
        #expect(reloaded.frontmatter.relationIDs(forPropertyID: propID) == [])
    }

    // MARK: - Items

    @Test("item: commit .relation([id]) for a tier id writes ROOT tier1, not properties")
    func itemTierRelationRoutesToRoot() async throws {
        let (nexus, type, manager) = try await setupItemTypeRoot()
        defer { TempNexus.cleanup(nexus) }

        _ = try await manager.createItem(name: "I", inTypeRoot: type)
        let item = manager.items(in: type).first!
        let url = NexusPaths.itemFileURL(
            forTitle: item.title,
            in: NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: type.title)
        )

        try await manager.updateItemProperty(
            item,
            propertyID: ReservedPropertyID.tier1,
            newValue: .relation(["01TARGET"]),
            type: type,
            collection: nil
        )

        let reloaded = try Item.load(from: url)
        #expect(reloaded.tier1 == ["01TARGET"])
        #expect(reloaded.properties[ReservedPropertyID.tier1] == nil)
    }

    @Test("item: commit .relation([id]) for a user relation id stores it in properties")
    func itemUserRelationRoutesToProperties() async throws {
        let (nexus, type, manager) = try await setupItemTypeRoot()
        defer { TempNexus.cleanup(nexus) }

        _ = try await manager.createItem(name: "I", inTypeRoot: type)
        let item = manager.items(in: type).first!
        let propID = ReservedPropertyID.mintUserPropertyID()
        let url = NexusPaths.itemFileURL(
            forTitle: item.title,
            in: NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: type.title)
        )

        try await manager.updateItemProperty(
            item,
            propertyID: propID,
            newValue: .relation(["01TARGET"]),
            type: type,
            collection: nil
        )

        let reloaded = try Item.load(from: url)
        #expect(reloaded.relationIDs(forPropertyID: propID) == ["01TARGET"])
        #expect(reloaded.properties[propID] == .relation(["01TARGET"]))
        #expect(reloaded.tier1 == [])
    }

    @Test("item: commit .relation([]) for a tier clears root, for a user relation omits the key")
    func itemEmptyRelationsBehavePerAdapter() async throws {
        let (nexus, type, manager) = try await setupItemTypeRoot()
        defer { TempNexus.cleanup(nexus) }

        _ = try await manager.createItem(name: "I", inTypeRoot: type)
        let item = manager.items(in: type).first!
        let propID = ReservedPropertyID.mintUserPropertyID()
        let url = NexusPaths.itemFileURL(
            forTitle: item.title,
            in: NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: type.title)
        )

        // Seed both a tier and a user relation.
        try await manager.updateItemProperty(
            item, propertyID: ReservedPropertyID.tier1,
            newValue: .relation(["01A"]), type: type, collection: nil
        )
        try await manager.updateItemProperty(
            manager.items(in: type).first!, propertyID: propID,
            newValue: .relation(["01B"]), type: type, collection: nil
        )

        // Clear both via empty .relation.
        try await manager.updateItemProperty(
            manager.items(in: type).first!, propertyID: ReservedPropertyID.tier1,
            newValue: .relation([]), type: type, collection: nil
        )
        try await manager.updateItemProperty(
            manager.items(in: type).first!, propertyID: propID,
            newValue: .relation([]), type: type, collection: nil
        )

        let reloaded = try Item.load(from: url)
        #expect(reloaded.tier1 == [])
        #expect(reloaded.properties[ReservedPropertyID.tier1] == nil)
        #expect(reloaded.properties[propID] == nil)
    }

    // MARK: - Harness

    /// Page-Type-root harness — mirrors PageContentManagerUpdatePageTests.setup
    /// (vault-root variant; no collection materialized).
    private func setupPageTypeRoot() async throws -> (Nexus, PageType, PageContentManager) {
        let nexus = try TempNexus.make()
        let vault = PageType(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: "V", in: nexus))

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, vault, manager)
    }

    /// Item-Type-root harness — mirrors ItemContentManagerTests.setupTypeRoot.
    private func setupItemTypeRoot() async throws -> (Nexus, ItemType, ItemContentManager) {
        let nexus = try TempNexus.make()
        let itemType = ItemType(
            id: ULID.generate(), title: "T", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        let typeFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "T")
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try itemType.save(to: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "T"))

        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, itemType, manager)
    }
}
