import Foundation
import Testing

@testable import Pommora

/// Pages-side CRUD tests for PageContentManager (PageCollection-scoped).
///
/// ParadigmV2 (Task 5.5 + 5.6): ContentManager was split into PageContentManager
/// (Pages) and ItemContentManager (Items). Item-side tests live in
/// `PommoraTests/Items/ItemContentManagerTests.swift`.
@MainActor
@Suite("PageContentManager")
struct PageContentManagerTests {

    @Test("createPage writes .md with frontmatter scaffold")
    func createPage() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, vault: vault)
        let url = NexusPaths.pageFileURL(forTitle: "Notes", in: coll.folderURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let pages = manager.pages(in: coll)
        #expect(pages.count == 1)
        #expect(pages.first?.title == "Notes")

        let loaded = try PageFile.load(from: url)
        #expect(!loaded.frontmatter.id.isEmpty)
        #expect(loaded.body == "")
        #expect(loaded.frontmatter.createdAt.timeIntervalSince1970 > 0)
    }

    @Test("renamePage moves file + updates pages list")
    func renamePage() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        try await manager.createPage(name: "Notes", in: coll, vault: vault)
        let page = manager.pages(in: coll).first!

        try await manager.renamePage(page, to: "Ideas", in: coll, vault: vault)
        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Notes", in: coll.folderURL).path
            ))
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Ideas", in: coll.folderURL).path
            ))
        #expect(manager.pages(in: coll).first?.title == "Ideas")
    }

    @Test("deletePage removes file")
    func deletes() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        try await manager.createPage(name: "P", in: coll, vault: vault)
        let page = manager.pages(in: coll).first!
        let pageURL = NexusPaths.pageFileURL(forTitle: "P", in: coll.folderURL)

        try await manager.deletePage(page, in: coll)

        #expect(manager.pages(in: coll).isEmpty)
        // File no longer at original location
        #expect(!FileManager.default.fileExists(atPath: pageURL.path))

        // File now in .trash, preserving relative path under nexus root
        // (flatlayout: PageType + PageCollection folders live at the nexus root).
        let trashPage = NexusPaths.trashDir(in: nexus).appendingPathComponent("V/C/P.md")
        #expect(FileManager.default.fileExists(atPath: trashPage.path))
    }

    @Test("loadAll discovers existing .md in a PageCollection")
    func loadExisting() async throws {
        let (nexus, _, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        try FixtureFiles.write(
            "---\nid: 01HPRE\ncreated_at: 2025-01-01T00:00:00Z\n---\n\nbody\n",
            to: NexusPaths.pageFileURL(forTitle: "Pre", in: coll.folderURL)
        )

        await manager.loadAll(for: coll)
        #expect(manager.pages(in: coll).count == 1)
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
