import Foundation
import Testing

@testable import Pommora

/// PageContentManager.updatePage CRUD tests.
///
/// ParadigmV2 (Task 5.5): File-rename to
/// `PageContentManagerUpdatePageTests.swift` lands in Task 5.6.
@MainActor
@Suite("PageContentManager.updatePage")
struct ContentManagerUpdatePageTests {

    @Test("updatePage persists body to disk (PageCollection-scoped)")
    func updatePagePersistsBodyToDisk() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, vault: vault)
        let page = manager.pages(in: coll).first!

        try await manager.updatePage(page, body: "Hello world", in: coll, vault: vault)

        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.body == "Hello world")
    }

    @Test("updatePage preserves frontmatter (id, createdAt, properties, tiers)")
    func updatePagePreservesFrontmatter() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, vault: vault)
        let page = manager.pages(in: coll).first!
        let originalID = page.frontmatter.id
        let originalCreatedAt = page.frontmatter.createdAt

        try await manager.updatePage(page, body: "Some new body content", in: coll, vault: vault)

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

    @Test("updatePage persists body to disk (vault-root)")
    func updatePageInVaultRootPersists() async throws {
        let (nexus, vault, _, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "RootNotes", inVaultRoot: vault)
        let page = manager.pages(in: vault).first!

        try await manager.updatePage(page, body: "Root body", inVaultRoot: vault)

        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.body == "Root body")
        #expect(reloaded.frontmatter.id == page.frontmatter.id)
    }

    @Test("updatePage validator failure surfaces pendingError")
    func validatorFailureSurfacesPendingError() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, vault: vault)
        let page = manager.pages(in: coll).first!

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
            try await manager.updatePage(badPage, body: "anything", in: coll, vault: vault)
        }
        #expect(manager.pendingError != nil)

        // On-disk file should still be the original empty body — no garbage written.
        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.body == "")
    }

    @Test("updatePage IO failure surfaces pendingError")
    func ioFailureSurfacesPendingError() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, vault: vault)
        let page = manager.pages(in: coll).first!

        // Delete the PageCollection folder out from under us — `pageFile.save(to:)`
        // writes via atomic temp-file + rename, which requires the parent dir
        // to exist. Should throw.
        try FileManager.default.removeItem(at: coll.folderURL)

        await #expect(throws: (any Error).self) {
            try await manager.updatePage(page, body: "anything", in: coll, vault: vault)
        }
        #expect(manager.pendingError != nil)
    }

    private func setup() async throws -> (Nexus, PageType, PageCollection, PageContentManager) {
        let nexus = try TempNexus.make()
        let vault = PageType(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: "V", in: nexus))

        let collFolder = NexusPaths.collectionFolderURL(forTitle: "C", inVaultTitled: "V", in: nexus)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = PageCollection(
            id: ULID.generate(),
            typeID: vault.id,
            title: "C",
            folderURL: collFolder,
            modifiedAt: Date()
        )

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, vault, coll, manager)
    }
}
