import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("PageTypeManager+FolderCRUD")
struct PageTypeManagerFolderCRUDTests {

    // MARK: - Setup helper

    private func setup() async throws -> (
        nexus: Nexus, manager: PageTypeManager,
        pageType: PageType, collection: PageCollection
    ) {
        let nexus = try TempNexus.make()
        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()
        try await manager.createPageType(name: "Research", icon: nil)
        let pt = manager.types.first!
        try await manager.createPageCollection(name: "Sources", inPageType: pt)
        let coll = manager.pageCollections(in: pt).first!
        return (nexus, manager, pt, coll)
    }

    // MARK: - createFolder

    @Test("createFolder writes _folder.json sidecar")
    func createFolder() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        let f = try await env.manager.createFolder(in: env.collection, title: "Topic A")

        let folderURL = NexusPaths.folderFolderURL(
            in: env.nexus.rootURL,
            typeFolderName: "Research",
            collectionFolderName: "Sources",
            folderFolderName: "Topic A"
        )
        let metaURL = NexusPaths.folderMetadataURL(
            in: env.nexus.rootURL,
            typeFolderName: "Research",
            collectionFolderName: "Sources",
            folderFolderName: "Topic A"
        )
        #expect(FileManager.default.fileExists(atPath: folderURL.path))
        #expect(FileManager.default.fileExists(atPath: metaURL.path))
        #expect(f.title == "Topic A")
        #expect(f.typeID == env.pageType.id)
        #expect(f.collectionID == env.collection.id)
    }

    @Test("createFolder appends to foldersByCollection")
    func createFolderAppends() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        _ = try await env.manager.createFolder(in: env.collection, title: "Topic A")
        _ = try await env.manager.createFolder(in: env.collection, title: "Topic B")

        let folders = env.manager.folders(in: env.collection)
        #expect(folders.count == 2)
        #expect(folders.map(\.title).sorted() == ["Topic A", "Topic B"])
    }

    @Test("createFolder mints default Table view via parent PageType property schema")
    func createFolderMintsDefaultView() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        let f = try await env.manager.createFolder(in: env.collection, title: "Topic A")
        #expect(f.views.count == 1)
        #expect(f.views[0].type == .table)
    }

    @Test("createFolder validates against duplicate title in same Collection")
    func createFolderDuplicate() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        _ = try await env.manager.createFolder(in: env.collection, title: "Topic A")
        await #expect(throws: FolderValidator.ValidationError.duplicateTitle) {
            _ = try await env.manager.createFolder(in: env.collection, title: "topic a")
        }
    }

    @Test("createFolder allows same title across different Collections")
    func createFolderCrossCollection() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        try await env.manager.createPageCollection(name: "Books", inPageType: env.pageType)
        let books = env.manager.pageCollections(in: env.pageType)
            .first(where: { $0.title == "Books" })!

        _ = try await env.manager.createFolder(in: env.collection, title: "Topic A")
        // Same title in a different Collection must succeed.
        _ = try await env.manager.createFolder(in: books, title: "Topic A")

        #expect(env.manager.folders(in: env.collection).count == 1)
        #expect(env.manager.folders(in: books).count == 1)
    }

    @Test("createFolder accepts custom icon")
    func createFolderWithIcon() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        let f = try await env.manager.createFolder(
            in: env.collection, title: "Topic A", icon: "books.vertical"
        )
        #expect(f.icon == "books.vertical")

        // Sidecar reflects the icon too.
        let metaURL = NexusPaths.folderMetadataURL(
            in: env.nexus.rootURL,
            typeFolderName: "Research",
            collectionFolderName: "Sources",
            folderFolderName: "Topic A"
        )
        let reloaded = try Folder.load(from: metaURL)
        #expect(reloaded.icon == "books.vertical")
    }

    // MARK: - renameFolder

    @Test("renameFolder moves the on-disk folder + updates the sidecar")
    func renameFolderMoves() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        let f = try await env.manager.createFolder(in: env.collection, title: "Topic A")
        try await env.manager.renameFolder(f, to: "Topic Alpha")

        let oldURL = NexusPaths.folderFolderURL(
            in: env.nexus.rootURL,
            typeFolderName: "Research", collectionFolderName: "Sources",
            folderFolderName: "Topic A"
        )
        let newURL = NexusPaths.folderFolderURL(
            in: env.nexus.rootURL,
            typeFolderName: "Research", collectionFolderName: "Sources",
            folderFolderName: "Topic Alpha"
        )
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(FileManager.default.fileExists(atPath: newURL.path))
    }

    @Test("renameFolder preserves icon + views across rename")
    func renameFolderPreservesState() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        let f = try await env.manager.createFolder(
            in: env.collection, title: "Topic A", icon: "books.vertical"
        )
        try await env.manager.renameFolder(f, to: "Topic Alpha")

        let renamed = env.manager.folders(in: env.collection).first!
        #expect(renamed.title == "Topic Alpha")
        #expect(renamed.icon == "books.vertical")
        #expect(renamed.views.count == 1)
    }

    @Test("renameFolder rejects duplicate sibling title")
    func renameFolderDuplicate() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        let a = try await env.manager.createFolder(in: env.collection, title: "Topic A")
        _ = try await env.manager.createFolder(in: env.collection, title: "Topic B")

        await #expect(throws: FolderValidator.ValidationError.duplicateTitle) {
            try await env.manager.renameFolder(a, to: "Topic B")
        }
    }

    // MARK: - deleteFolder

    @Test("deleteFolder moves the on-disk folder to .trash")
    func deleteFolderTrashesOnDisk() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        let f = try await env.manager.createFolder(in: env.collection, title: "Topic A")
        try await env.manager.deleteFolder(f)

        let folderURL = NexusPaths.folderFolderURL(
            in: env.nexus.rootURL,
            typeFolderName: "Research", collectionFolderName: "Sources",
            folderFolderName: "Topic A"
        )
        #expect(!FileManager.default.fileExists(atPath: folderURL.path))
        #expect(env.manager.folders(in: env.collection).isEmpty)

        let trashURL = NexusPaths.trashDir(in: env.nexus)
            .appendingPathComponent("Research/Sources/Topic A")
        #expect(FileManager.default.fileExists(atPath: trashURL.path))
    }

    // MARK: - reorderFolders

    @Test("reorderFolders persists folder_order on the Collection sidecar")
    func reorderFoldersPersists() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        let a = try await env.manager.createFolder(in: env.collection, title: "A")
        _ = try await env.manager.createFolder(in: env.collection, title: "B")
        _ = try await env.manager.createFolder(in: env.collection, title: "C")

        // Move A from index 0 to past the end (becomes last).
        env.manager.reorderFolders(in: env.collection, fromOffsets: IndexSet(integer: 0), toOffset: 3)

        let result = env.manager.folders(in: env.collection)
        #expect(result.last?.id == a.id)

        // Reload from disk to confirm persistence.
        let collMetaURL = env.collection.folderURL.appendingPathComponent(
            NexusPaths.pageCollectionSidecarFilename
        )
        let reloaded = try PageCollection.load(from: collMetaURL)
        #expect(reloaded.folderOrder?.last == a.id)
    }

    // MARK: - loadAll

    @Test("loadAll discovers Folders inside Collections + populates foldersByCollection")
    func loadAllDiscovers() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        _ = try await env.manager.createFolder(in: env.collection, title: "Topic A")
        _ = try await env.manager.createFolder(in: env.collection, title: "Topic B")

        // Fresh manager re-loads from disk.
        let fresh = PageTypeManager(nexus: env.nexus)
        await fresh.loadAll()

        let pt = fresh.types.first!
        let coll = fresh.pageCollections(in: pt).first!
        let folders = fresh.folders(in: coll)
        #expect(folders.count == 2)
        #expect(Set(folders.map(\.title)) == ["Topic A", "Topic B"])
    }

    @Test("loadAll mints default Table view on Folder with empty views (forward-compat)")
    func loadAllMintsDefaultView() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        // Construct a Folder sidecar directly on disk WITHOUT any views (mimics
        // an F.1.i auto-tagged folder, or a hand-edited legacy sidecar).
        let folderURL = NexusPaths.folderFolderURL(
            in: env.nexus.rootURL,
            typeFolderName: "Research",
            collectionFolderName: "Sources",
            folderFolderName: "Cold Folder"
        )
        try FileManager.default.createDirectory(
            at: folderURL, withIntermediateDirectories: true
        )
        let metaURL = NexusPaths.folderMetadataURL(
            in: env.nexus.rootURL,
            typeFolderName: "Research",
            collectionFolderName: "Sources",
            folderFolderName: "Cold Folder"
        )
        let raw = Folder(
            id: ULID.generate(),
            typeID: env.pageType.id,
            collectionID: env.collection.id,
            title: "Cold Folder",
            folderURL: folderURL,
            modifiedAt: Date(),
            views: []
        )
        try raw.save(to: metaURL)

        let fresh = PageTypeManager(nexus: env.nexus)
        await fresh.loadAll()

        let pt = fresh.types.first!
        let coll = fresh.pageCollections(in: pt).first!
        let folder = fresh.folders(in: coll).first(where: { $0.title == "Cold Folder" })
        #expect(folder?.views.count == 1)
        #expect(folder?.views.first?.type == .table)
    }

    // MARK: - Rename cascades

    @Test("renamePageCollection rebuilds Folder folderURLs")
    func renameCollectionRebuildsFolderURLs() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        _ = try await env.manager.createFolder(in: env.collection, title: "Topic A")
        try await env.manager.renamePageCollection(env.collection, to: "Articles")

        let newCollection = env.manager.pageCollections(in: env.pageType)
            .first(where: { $0.title == "Articles" })!
        let folder = env.manager.folders(in: newCollection).first!
        let expectedURL = NexusPaths.folderFolderURL(
            in: env.nexus.rootURL,
            typeFolderName: "Research",
            collectionFolderName: "Articles",
            folderFolderName: "Topic A"
        )
        #expect(folder.folderURL == expectedURL)
    }

    @Test("renamePageType rebuilds nested Folder folderURLs")
    func renamePageTypeRebuildsFolderURLs() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        _ = try await env.manager.createFolder(in: env.collection, title: "Topic A")
        try await env.manager.renamePageType(env.pageType, to: "Knowledge")

        let renamedType = env.manager.types.first!
        let coll = env.manager.pageCollections(in: renamedType).first!
        let folder = env.manager.folders(in: coll).first!
        let expectedURL = NexusPaths.folderFolderURL(
            in: env.nexus.rootURL,
            typeFolderName: "Knowledge",
            collectionFolderName: "Sources",
            folderFolderName: "Topic A"
        )
        #expect(folder.folderURL == expectedURL)
    }

    @Test("deletePageCollection clears foldersByCollection for that Collection")
    func deletePageCollectionClearsFolders() async throws {
        let env = try await setup()
        defer { TempNexus.cleanup(env.nexus) }

        _ = try await env.manager.createFolder(in: env.collection, title: "Topic A")
        try await env.manager.deletePageCollection(env.collection)
        #expect(env.manager.folders(in: env.collection).isEmpty)
    }
}
