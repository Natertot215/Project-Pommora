import Foundation
import GRDB
import Testing

@testable import Pommora

/// Nexus-wide per-kind title uniqueness (Connections invariant). The
/// container-scoped `enforceTitleUniqueness` only sees the in-memory siblings of
/// one Collection / Vault, so a duplicate title across DIFFERENT vaults (or
/// types) slips through today. The index-backed `enforceNexusWideTitleUniqueness`
/// guard added on each `+CRUD` extension closes that gap: an in-app create/rename
/// to a title that exists ANYWHERE in the nexus (same kind) is rejected.
///
/// Pages and Items are SEPARATE kinds — a Page and an Item MAY share a title
/// (`titleExists(kind:)` scopes to one table).
///
/// Fixture mirrors `ConnectionLiveUpdateTests` / `UnlinkTierTests`: a TempNexus +
/// PommoraIndex with the parent Types/Collections seeded into the index, and an
/// `IndexUpdater` wired to the manager (the guard early-returns when the updater
/// is nil, so the wiring is load-bearing).
@MainActor
@Suite("NexusWideUniquenessTests")
struct NexusWideUniquenessTests {

    // MARK: - Test 1: cross-vault Page dup rejected

    @Test("createPage rejects a title already used in a DIFFERENT vault")
    func crossVaultPageDupRejected() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let v1 = try makeVault(in: nexus, index: index, title: "V1")
        let v2 = try makeVault(in: nexus, index: index, title: "V2")
        let c1 = try makePageCollection(in: nexus, vault: v1, index: index, title: "C1")
        let c2 = try makePageCollection(in: nexus, vault: v2, index: index, title: "C2")

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)

        _ = try await manager.createPage(name: "X", in: c1, vault: v1)

        await #expect(throws: PageCRUDError.duplicateTitle) {
            _ = try await manager.createPage(name: "X", in: c2, vault: v2)
        }
    }

    // MARK: - Test 2: cross-type Item dup rejected

    @Test("createItem rejects a title already used in a DIFFERENT type")
    func crossTypeItemDupRejected() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let t1 = try makeItemType(in: nexus, index: index, title: "T1")
        let t2 = try makeItemType(in: nexus, index: index, title: "T2")

        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)

        _ = try await manager.createItem(name: "X", inTypeRoot: t1)

        await #expect(throws: ItemCRUDError.duplicateTitle) {
            _ = try await manager.createItem(name: "X", inTypeRoot: t2)
        }
    }

    // MARK: - Test 3: cross-kind shared title allowed

    @Test("a Page and an Item MAY share a title (separate kinds)")
    func crossKindSharedTitleAllowed() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        // ONE index + ONE updater shared by BOTH managers over the SAME nexus.
        let updater = IndexUpdater(index)

        let vault = try makeVault(in: nexus, index: index, title: "V")
        let itemType = try makeItemType(in: nexus, index: index, title: "T")

        let pageManager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        pageManager.indexUpdater = updater
        let itemManager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        itemManager.indexUpdater = updater

        // Page "Shared" must NOT block Item "Shared" — different table.
        _ = try await pageManager.createPage(name: "Shared", inVaultRoot: vault)
        _ = try await itemManager.createItem(name: "Shared", inTypeRoot: itemType)
        // Reaching here without a throw is the assertion; pendingError stays clean.
        #expect(pageManager.pendingError == nil)
        #expect(itemManager.pendingError == nil)
    }

    // MARK: - Fixtures (mirror UnlinkTierTests)

    private func makeVault(in nexus: Nexus, index: PommoraIndex, title: String) throws -> PageType {
        let vault = PageType(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folder = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: title, in: nexus))
        try IndexUpdater(index).upsertPageType(vault)
        return vault
    }

    private func makePageCollection(
        in nexus: Nexus, vault: PageType, index: PommoraIndex, title: String
    ) throws -> PageCollection {
        let folder = NexusPaths.collectionFolderURL(forTitle: title, inVaultTitled: vault.title, in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let coll = PageCollection(
            id: ULID.generate(), typeID: vault.id, title: title, folderURL: folder, modifiedAt: Date()
        )
        try coll.save(to: folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
        try IndexUpdater(index).upsertPageCollection(coll)
        return coll
    }

    private func makeItemType(in nexus: Nexus, index: PommoraIndex, title: String) throws -> ItemType {
        let itemType = ItemType(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: title)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try itemType.save(to: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: title))
        try IndexUpdater(index).upsertItemType(itemType)
        return itemType
    }
}
