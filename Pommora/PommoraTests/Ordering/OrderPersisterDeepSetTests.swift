import Foundation
import Testing

@testable import Pommora

/// Verifies that setPageSetOrder writes to the correct sidecar at any depth.
/// Depth-1 parent containers carry `_pagecollection.json`; depth-2+ Sets carry
/// `_pageset.json`. The persister must resolve by existence, not hard-code.
@MainActor
@Suite("OrderPersisterDeepSetTests")
struct OrderPersisterDeepSetTests {

    @Test("setPageSetOrder on a depth-2 Set writes to _pageset.json, not _pagecollection.json")
    func deepSetReorderWritesToPageSetSidecar() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vault = try makePageCollection(nexus: nexus, title: "Notes")
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault)

        // SetA is a depth-2 Set (parent is a Collection). It carries _pageset.json.
        let setA = try makePageSet(title: "SetA", in: coll)

        // SubB is a depth-3 Set (parent is SetA).
        let subB1 = try makePageSet(title: "SubB1", in: setA)
        let subB2 = try makePageSet(title: "SubB2", in: setA)

        // Reorder sub-sets inside SetA. The order must persist to SetA's _pageset.json.
        try OrderPersister.setPageSetOrder([subB2.id, subB1.id], in: setA)

        // Read back from _pageset.json and confirm the order was written there.
        let setASidecarURL = setA.folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: setASidecarURL.path))

        let reloaded = try PageSet.load(from: setASidecarURL)
        #expect(reloaded.setOrder == [subB2.id, subB1.id])

        // _pagecollection.json must NOT exist inside SetA (it's not a collection).
        let wrongSidecarURL = setA.folderURL.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        #expect(!FileManager.default.fileExists(atPath: wrongSidecarURL.path))
    }

    @Test("setPageSetOrder on a depth-1 Collection (no _pageset.json) writes to _pagecollection.json")
    func collectionReorderWritesToCollectionSidecar() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vault = try makePageCollection(nexus: nexus, title: "Notes")
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault)
        let setA = try makePageSet(title: "SetA", in: coll)
        let setB = try makePageSet(title: "SetB", in: coll)

        // Reorder sets inside coll. coll has _pagecollection.json, no _pageset.json.
        try OrderPersister.setPageSetOrder([setB.id, setA.id], in: coll)

        let collSidecarURL = coll.folderURL.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        let reloaded = try PageSet.load(from: collSidecarURL)
        #expect(reloaded.setOrder == [setB.id, setA.id])
    }

    // MARK: - Helpers

    @discardableResult
    private func makePageCollection(nexus: Nexus, title: String) throws -> PageCollection {
        let vault = PageCollection(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folderURL = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: title, in: nexus))
        return vault
    }

    @discardableResult
    private func makePageCollection(nexus: Nexus, title: String, in pageCollection: PageCollection) throws -> PageSet {
        let folderURL = NexusPaths.collectionFolderURL(
            forTitle: title, inVaultTitled: pageCollection.title, in: nexus)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let coll = PageSet(
            id: ULID.generate(), parentID: pageCollection.id, title: title,
            folderURL: folderURL, modifiedAt: Date()
        )
        try coll.save(to: folderURL.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
        return coll
    }

    @discardableResult
    private func makePageSet(title: String, in parent: PageSet) throws -> PageSet {
        let folderURL = parent.folderURL.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let set = PageSet(
            id: ULID.generate(), parentID: parent.id, title: title,
            folderURL: folderURL, modifiedAt: Date()
        )
        try set.save(to: folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        return set
    }
}
