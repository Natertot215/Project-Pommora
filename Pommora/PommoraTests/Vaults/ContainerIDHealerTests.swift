import Foundation
import Testing

@testable import Pommora

/// Duplicate-ULID healing tests.
///
/// Finder-duplicating a container folder clones its sidecar id. On load, the
/// first folder discovered keeps the id; every later duplicate gets a fresh
/// ULID minted + its sidecar rewritten via `ContainerIDHealer`, wired into
/// `PageTypeManager.loadAll` (Types + Collections) and
/// `PageSetManager.loadAll` (Sets).
@MainActor
@Suite("ContainerIDHealer")
struct ContainerIDHealerTests {

    // MARK: - Fixtures

    private struct Fixture {
        let nexus: Nexus
        let typeManager: PageTypeManager
        let setManager: PageSetManager
        let pageType: PageType
        let collection: PageCollection
    }

    /// Vault "Notes" + Collection "Inbox" via CRUD; both managers loaded.
    private func makeFixture() async throws -> Fixture {
        let nexus = try TempNexus.make()
        let typeManager = PageTypeManager(nexus: nexus)
        await typeManager.loadAll()
        try await typeManager.createPageType(name: "Notes", icon: nil)
        let pageType = typeManager.types.first!
        try await typeManager.createPageCollection(name: "Inbox", inPageType: pageType)
        let collection = typeManager.pageCollections(in: pageType).first!
        let setManager = PageSetManager(nexus: nexus)
        await setManager.loadAll(collections: [collection])
        return Fixture(
            nexus: nexus, typeManager: typeManager, setManager: setManager,
            pageType: pageType, collection: collection
        )
    }

    // MARK: - Duplicated Collection folders

    @Test("loadAll re-IDs a Finder-duplicated Collection folder and rewrites its sidecar")
    func duplicatedCollectionHealed() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        let originalID = fx.collection.id
        let copyFolder = fx.collection.folderURL.deletingLastPathComponent()
            .appendingPathComponent("Inbox 2", isDirectory: true)
        try FileManager.default.copyItem(at: fx.collection.folderURL, to: copyFolder)

        await fx.typeManager.loadAll()

        // Cache: two Collections, distinct ids, exactly one keeps the original.
        let pageType = fx.typeManager.types.first!
        let cols = fx.typeManager.pageCollections(in: pageType)
        #expect(cols.count == 2)
        let ids = Set(cols.map(\.id))
        #expect(ids.count == 2)
        #expect(cols.filter { $0.id == originalID }.count == 1)

        // Disk: both sidecars carry the distinct cache ids.
        let diskIDs = try Set(
            cols.map {
                try PageCollection.load(
                    from: $0.folderURL.appendingPathComponent(
                        NexusPaths.pageCollectionSidecarFilename)
                ).id
            })
        #expect(diskIDs == ids)

        // Idempotent: a second load leaves both disk ids unchanged.
        await fx.typeManager.loadAll()
        let diskIDs2 = try Set(
            cols.map {
                try PageCollection.load(
                    from: $0.folderURL.appendingPathComponent(
                        NexusPaths.pageCollectionSidecarFilename)
                ).id
            })
        #expect(diskIDs2 == diskIDs)
    }

    // MARK: - Duplicated Set folders

    @Test("loadAll re-IDs a Finder-duplicated Set folder and rewrites its sidecar")
    func duplicatedSetHealed() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        let set = try await fx.setManager.createPageSet(name: "Drafts", in: fx.collection)
        let copyFolder = fx.collection.folderURL.appendingPathComponent(
            "Drafts 2", isDirectory: true)
        try FileManager.default.copyItem(at: set.folderURL, to: copyFolder)

        await fx.setManager.loadAll(collections: [fx.collection])

        // Cache: two Sets, distinct ids, exactly one keeps the original.
        let sets = fx.setManager.pageSets(in: fx.collection)
        #expect(sets.count == 2)
        let ids = Set(sets.map(\.id))
        #expect(ids.count == 2)
        #expect(sets.filter { $0.id == set.id }.count == 1)

        // Disk: both sidecars carry the distinct cache ids.
        let diskIDs = try Set(
            sets.map {
                try PageSet.load(
                    from: $0.folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
                ).id
            })
        #expect(diskIDs == ids)

        // Idempotent: a second load leaves both disk ids unchanged.
        await fx.setManager.loadAll(collections: [fx.collection])
        let diskIDs2 = try Set(
            sets.map {
                try PageSet.load(
                    from: $0.folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
                ).id
            })
        #expect(diskIDs2 == diskIDs)
    }

    // MARK: - Duplicated Type folder (cross-type collection clones)

    @Test("a duplicated Type folder gets a fresh Type id and its cloned Collections re-ID + re-point")
    func duplicatedTypeHealed() async throws {
        let fx = try await makeFixture()
        defer { TempNexus.cleanup(fx.nexus) }

        let typeFolder = fx.collection.folderURL.deletingLastPathComponent()
        let copyFolder = fx.nexus.rootURL.appendingPathComponent("Notes 2", isDirectory: true)
        try FileManager.default.copyItem(at: typeFolder, to: copyFolder)

        await fx.typeManager.loadAll()

        // Two Types with distinct ids; exactly one keeps the original.
        let types = fx.typeManager.types
        #expect(types.count == 2)
        #expect(Set(types.map(\.id)).count == 2)
        #expect(types.filter { $0.id == fx.pageType.id }.count == 1)

        // The cloned Collection ids are healed across Types (load-wide
        // namespace), and each Collection points at its CONTAINING Type.
        let allCols = types.flatMap { fx.typeManager.pageCollections(in: $0) }
        #expect(allCols.count == 2)
        #expect(Set(allCols.map(\.id)).count == 2)
        for type in types {
            for col in fx.typeManager.pageCollections(in: type) {
                #expect(col.typeID == type.id)
            }
        }
    }
}
