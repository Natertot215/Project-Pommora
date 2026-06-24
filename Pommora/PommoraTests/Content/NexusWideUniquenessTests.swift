import Foundation
import GRDB
import Testing

@testable import Pommora

/// Nexus-wide title uniqueness (Connections invariant). The
/// container-scoped `enforceTitleUniqueness` only sees the in-memory siblings of
/// one Collection / Vault, so a duplicate title across DIFFERENT vaults slips
/// through today. The index-backed `enforceNexusWideTitleUniqueness`
/// guard added on each `+CRUD` extension closes that gap: an in-app create/rename
/// to a title that exists ANYWHERE in the nexus is rejected.
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
        let c1 = try makePageSet(in: nexus, pageCollection: v1, index: index, title: "C1")
        let c2 = try makePageSet(in: nexus, pageCollection: v2, index: index, title: "C2")

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)

        _ = try await manager.createPage(name: "X", in: c1, pageCollection: v1)

        await #expect(throws: PageCRUDError.duplicateTitle) {
            _ = try await manager.createPage(name: "X", in: c2, pageCollection: v2)
        }
    }

    // MARK: - Fixtures (mirror UnlinkTierTests)

    private func makeVault(in nexus: Nexus, index: PommoraIndex, title: String) throws -> PageCollection {
        let vault = PageCollection(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folder = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: title, in: nexus))
        try IndexUpdater(index).upsertPageCollection(vault)
        return vault
    }

    private func makePageSet(
        in nexus: Nexus, pageCollection: PageCollection, index: PommoraIndex, title: String
    ) throws -> PageSet {
        let folder = NexusPaths.collectionFolderURL(forTitle: title, inVaultTitled: pageCollection.title, in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let coll = PageSet(
            id: ULID.generate(), parentID: pageCollection.id, title: title, folderURL: folder, modifiedAt: Date()
        )
        try coll.save(to: folder.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        try IndexUpdater(index).upsertPageCollection(coll)
        return coll
    }

}
