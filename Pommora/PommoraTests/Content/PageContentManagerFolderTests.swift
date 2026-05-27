import Foundation
import Testing

@testable import Pommora

/// F.1.h — Folder-scoped Page CRUD + load + reorder.
///
/// Mirrors the Collection-scoped tests in `PageContentManagerTests.swift`
/// but routes everything through the third tier (Folder). Verifies that:
///   - Pages inside a Folder land in `pagesByFolder[folder.id]`, not in
///     `pagesByCollection`.
///   - `loadAll(for: collection)` excludes Folder-tagged sub-folders so
///     Folder-resident Pages don't double-count.
///   - Reorder persists to the Folder's `_folder.json` `page_order` field.
@MainActor
@Suite("PageContentManager+Folders")
struct PageContentManagerFolderTests {

    // MARK: - Setup helper

    private func setup() async throws -> (
        nexus: Nexus,
        vault: PageType,
        collection: PageCollection,
        folder: Folder,
        manager: PageContentManager,
        ptm: PageTypeManager
    ) {
        let nexus = try TempNexus.make()
        let ptm = PageTypeManager(nexus: nexus)
        await ptm.loadAll()
        try await ptm.createPageType(name: "Research", icon: nil)
        let vault = ptm.types.first!
        try await ptm.createPageCollection(name: "Sources", inPageType: vault)
        let coll = ptm.pageCollections(in: vault).first!
        let folder = try await ptm.createFolder(in: coll, title: "Topic A")

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, vault, coll, folder, manager, ptm)
    }

    // MARK: - createPage

    @Test("createPage writes .md inside folder.folderURL")
    func createPageWritesInsideFolder() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        try await env.manager.createPage(name: "Note 1", in: env.folder, vault: env.vault)
        let url = NexusPaths.pageFileURL(forTitle: "Note 1", in: env.folder.folderURL)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let pages = env.manager.pages(in: env.folder)
        #expect(pages.count == 1)
        #expect(pages.first?.title == "Note 1")
    }

    @Test("createPage places file at three-tier path, not Collection root")
    func createPageThreeTierPath() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        try await env.manager.createPage(name: "Note 1", in: env.folder, vault: env.vault)
        // Three-tier on-disk path: <nexus>/Research/Sources/Topic A/Note 1.md
        let expected = env.nexus.rootURL
            .appendingPathComponent("Research")
            .appendingPathComponent("Sources")
            .appendingPathComponent("Topic A")
            .appendingPathComponent("Note 1.md")
        #expect(FileManager.default.fileExists(atPath: expected.path))
    }

    @Test("createPage in folder does NOT appear in pagesByCollection")
    func createPageScopedToFolderOnly() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        try await env.manager.createPage(name: "Note 1", in: env.folder, vault: env.vault)
        // Re-load Collection-scoped bucket from disk; Folder sub-folder must
        // be excluded from the Collection walk (F.1.h regression guard).
        await env.manager.loadAll(for: env.collection)
        #expect(env.manager.pages(in: env.collection).isEmpty)
        #expect(env.manager.pages(in: env.folder).count == 1)
    }

    // MARK: - renamePage

    @Test("renamePage moves file inside folder + updates list")
    func renamePage() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        try await env.manager.createPage(name: "Note 1", in: env.folder, vault: env.vault)
        let page = env.manager.pages(in: env.folder).first!

        try await env.manager.renamePage(page, to: "Note Two", in: env.folder, vault: env.vault)

        let oldURL = NexusPaths.pageFileURL(forTitle: "Note 1", in: env.folder.folderURL)
        let newURL = NexusPaths.pageFileURL(forTitle: "Note Two", in: env.folder.folderURL)
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(env.manager.pages(in: env.folder).first?.title == "Note Two")
    }

    // MARK: - deletePage

    @Test("deletePage removes file + clears from pagesByFolder")
    func deletePage() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        try await env.manager.createPage(name: "Note 1", in: env.folder, vault: env.vault)
        let page = env.manager.pages(in: env.folder).first!

        try await env.manager.deletePage(page, in: env.folder)

        let url = NexusPaths.pageFileURL(forTitle: "Note 1", in: env.folder.folderURL)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(env.manager.pages(in: env.folder).isEmpty)
    }

    // MARK: - updatePage (body)

    @Test("updatePage writes body to disk + preserves frontmatter")
    func updatePageBody() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        try await env.manager.createPage(name: "Note 1", in: env.folder, vault: env.vault)
        let page = env.manager.pages(in: env.folder).first!

        try await env.manager.updatePage(page, body: "hello", in: env.folder, vault: env.vault)

        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.body == "hello")
        #expect(reloaded.frontmatter.id == page.frontmatter.id)
    }

    // MARK: - loadAll (Folder-scoped)

    @Test("loadAll(for: folder) discovers existing .md in folder")
    func loadAllForFolder() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        let preURL = NexusPaths.pageFileURL(forTitle: "Pre", in: env.folder.folderURL)
        try FixtureFiles.write(
            "---\nid: 01HPRE\ncreated_at: 2025-01-01T00:00:00Z\n---\n\nbody\n",
            to: preURL
        )

        await env.manager.loadAll(for: env.folder)
        #expect(env.manager.pages(in: env.folder).count == 1)
        #expect(env.manager.pages(in: env.folder).first?.title == "Pre")
    }

    @Test("loadAll(for: collection) skips Folder sub-folders entirely")
    func loadAllForCollectionExcludesFolders() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        // Page directly at Collection root
        try FixtureFiles.write(
            "---\nid: 01HCOLL\ncreated_at: 2025-01-01T00:00:00Z\n---\n\nbody\n",
            to: NexusPaths.pageFileURL(forTitle: "RootPage", in: env.collection.folderURL)
        )
        // Page inside the Folder
        try FixtureFiles.write(
            "---\nid: 01HFOLD\ncreated_at: 2025-01-01T00:00:00Z\n---\n\nbody\n",
            to: NexusPaths.pageFileURL(forTitle: "FolderPage", in: env.folder.folderURL)
        )

        await env.manager.loadAll(for: env.collection)
        await env.manager.loadAll(for: env.folder)

        let collTitles = env.manager.pages(in: env.collection).map(\.title)
        let foldTitles = env.manager.pages(in: env.folder).map(\.title)
        #expect(collTitles == ["RootPage"])
        #expect(foldTitles == ["FolderPage"])
    }

    // MARK: - reorderPages (Folder-scoped)

    @Test("reorderPages(in folder:) persists new order to _folder.json")
    func reorderPersistsToSidecar() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        try await env.manager.createPage(name: "A", in: env.folder, vault: env.vault)
        try await env.manager.createPage(name: "B", in: env.folder, vault: env.vault)
        try await env.manager.createPage(name: "C", in: env.folder, vault: env.vault)

        // Move C (index 2) to the front.
        env.manager.reorderPages(
            in: env.folder, fromOffsets: IndexSet(integer: 2), toOffset: 0
        )

        let titles = env.manager.pages(in: env.folder).map(\.title)
        #expect(titles == ["C", "A", "B"])

        // Sidecar read-back: page_order reflects the new ID sequence.
        let metaURL = env.folder.folderURL
            .appendingPathComponent(NexusPaths.folderSidecarFilename)
        let reloaded = try Folder.load(from: metaURL)
        let expectedIDs = env.manager.pages(in: env.folder).map(\.id)
        #expect(reloaded.pageOrder == expectedIDs)
    }

    @Test("reorderPages is a no-op when offsets don't move anything")
    func reorderNoOp() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        try await env.manager.createPage(name: "A", in: env.folder, vault: env.vault)
        try await env.manager.createPage(name: "B", in: env.folder, vault: env.vault)

        // Move index 0 to offset 0 — no change.
        env.manager.reorderPages(
            in: env.folder, fromOffsets: IndexSet(integer: 0), toOffset: 0
        )

        // Sidecar's page_order should remain nil (no persistence on no-op).
        let metaURL = env.folder.folderURL
            .appendingPathComponent(NexusPaths.folderSidecarFilename)
        let reloaded = try Folder.load(from: metaURL)
        #expect(reloaded.pageOrder == nil)
    }

    // MARK: - resolveParent (3-tuple)

    @Test("resolveParent returns full Folder tuple for Folder-scoped Page")
    func resolveParentReturnsFolder() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        try await env.manager.createPage(name: "Note 1", in: env.folder, vault: env.vault)
        let page = env.manager.pages(in: env.folder).first!

        let parent = env.manager.resolveParent(for: page, pageTypeManager: env.ptm)
        #expect(parent?.vault.id == env.vault.id)
        #expect(parent?.collection?.id == env.collection.id)
        #expect(parent?.folder?.id == env.folder.id)
    }
}
