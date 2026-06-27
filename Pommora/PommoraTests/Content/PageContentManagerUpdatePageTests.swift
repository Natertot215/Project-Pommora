import Foundation
import Testing

@testable import Pommora

/// PageContentManager.updatePage CRUD tests.
@MainActor
@Suite("PageContentManager.updatePage")
struct PageContentManagerUpdatePageTests {

    @Test("updatePage persists body to disk (PageSet-scoped)")
    func updatePagePersistsBodyToDisk() async throws {
        let (nexus, collection, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, pageCollection: collection)
        let page = manager.pages(inCollection: coll).first!

        try await manager.updatePage(page, body: "Hello world", in: coll, pageCollection: collection)

        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.body == "Hello world")
    }

    @Test("updatePage preserves frontmatter (id, createdAt, properties, tiers)")
    func updatePagePreservesFrontmatter() async throws {
        let (nexus, collection, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, pageCollection: collection)
        let page = manager.pages(inCollection: coll).first!
        let originalID = page.frontmatter.id
        let originalCreatedAt = page.frontmatter.createdAt

        try await manager.updatePage(page, body: "Some new body content", in: coll, pageCollection: collection)

        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.frontmatter.id == originalID)
        #expect(
            reloaded.frontmatter.createdAt.timeIntervalSince1970
                == originalCreatedAt.timeIntervalSince1970
        )
        #expect(reloaded.frontmatter.tier1 == page.frontmatter.tier1)
        #expect(reloaded.frontmatter.tier2 == page.frontmatter.tier2)
        #expect(reloaded.frontmatter.tier3 == page.frontmatter.tier3)
        #expect(reloaded.frontmatter.icon == page.frontmatter.icon)
    }

    @Test("updatePage bumps modified_at to now on body save")
    func updatePageBumpsModifiedAt() async throws {
        let (nexus, collection, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, pageCollection: collection)
        var page = manager.pages(inCollection: coll).first!
        // Pin the in-memory stamp to the epoch so a real bump is unmistakable —
        // without the bump, updatePage would round-trip 1970 straight back to disk.
        page.frontmatter.modifiedAt = Date(timeIntervalSince1970: 0)

        try await manager.updatePage(page, body: "Hello", in: coll, pageCollection: collection)

        let reloaded = try PageFile.load(from: page.url)
        let modified = try #require(reloaded.frontmatter.modifiedAt)
        #expect(abs(modified.timeIntervalSinceNow) < 2)
    }

    @Test("createPage writes modified_at to disk (not just relying on the mtime fallback)")
    func createPageStampsModifiedAt() async throws {
        let (nexus, collection, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Fresh", in: coll, pageCollection: collection)
        let page = manager.pages(inCollection: coll).first!
        // Backdate the file mtime — if createPage truly stamped modified_at, load reads
        // the stored (now) stamp, not the backdated mtime fallback.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: page.url.path)

        let reloaded = try PageFile.load(from: page.url)
        let modified = try #require(reloaded.frontmatter.modifiedAt)
        #expect(abs(modified.timeIntervalSinceNow) < 5)  // the stored stamp (≈now), not 1970
    }

    @Test("updatePage persists body to disk (vault-root)")
    func updatePageInCollectionRootPersists() async throws {
        let (nexus, collection, _, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "RootNotes", inCollectionRoot: collection)
        let page = manager.pages(in: collection).first!

        try await manager.updatePage(page, body: "Root body", inCollectionRoot: collection)

        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.body == "Root body")
        #expect(reloaded.frontmatter.id == page.frontmatter.id)
    }

    @Test("updatePage validator failure surfaces pendingError")
    func validatorFailureSurfacesPendingError() async throws {
        let (nexus, collection, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, pageCollection: collection)
        let page = manager.pages(inCollection: coll).first!

        // Mutate the in-memory PageMeta to carry an invalid title — the validator
        // should reject it. (Real callers wouldn't do this, but a corrupted
        // PageMeta from a stale cache could trigger it; the contract is "throw,
        // surface pendingError, don't write garbage to disk".)
        let badPage = PageMeta(
            id: page.id,
            title: "Bad/Title",  // forward slash is invalid per PageValidator
            url: page.url,
            frontmatter: page.frontmatter
        )

        await #expect(throws: (any Error).self) {
            try await manager.updatePage(badPage, body: "anything", in: coll, pageCollection: collection)
        }
        #expect(manager.pendingError != nil)

        // On-disk file should still be the original empty body — no garbage written.
        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.body == "")
    }

    @Test("updatePage IO failure surfaces pendingError")
    func ioFailureSurfacesPendingError() async throws {
        let (nexus, collection, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, pageCollection: collection)
        let page = manager.pages(inCollection: coll).first!

        // Delete the PageSet folder out from under us — `pageFile.save(to:)`
        // writes via atomic temp-file + rename, which requires the parent dir
        // to exist. Should throw.
        try FileManager.default.removeItem(at: coll.folderURL)

        await #expect(throws: (any Error).self) {
            try await manager.updatePage(page, body: "anything", in: coll, pageCollection: collection)
        }
        #expect(manager.pendingError != nil)
    }

    private func setup() async throws -> (Nexus, PageCollection, PageSet, PageContentManager) {
        let nexus = try TempNexus.make()
        let collection = PageCollection(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        let collectionFolder = NexusPaths.collectionFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: collectionFolder, withIntermediateDirectories: true)
        try collection.save(to: NexusPaths.collectionMetadataURL(forTitle: "V", in: nexus))

        let collFolder = NexusPaths.setFolderURL(forTitle: "C", inCollectionTitled: "V", in: nexus)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = PageSet(
            id: ULID.generate(),
            parentID: collection.id,
            title: "C",
            folderURL: collFolder,
            modifiedAt: Date()
        )

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, collection, coll, manager)
    }
}
