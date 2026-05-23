import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("PageTypeManager")
struct PageTypeManagerTests {

    @Test("createPageType writes folder + _schema.json")
    func createPageType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createPageType(name: "Planner", icon: "folder")
        let folder = NexusPaths.vaultFolderURL(forTitle: "Planner", in: nexus)
        let meta = NexusPaths.vaultMetadataURL(forTitle: "Planner", in: nexus)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: meta.path))
        #expect(manager.types.count == 1)
        #expect(manager.types.first?.title == "Planner")
    }

    @Test("createPageCollection creates folder inside PageType")
    func createPageCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createPageType(name: "Planner", icon: nil)
        let pageType = manager.types.first!
        try await manager.createPageCollection(name: "Tasks", inPageType: pageType)

        let folder = NexusPaths.collectionFolderURL(
            forTitle: "Tasks", inVaultTitled: "Planner", in: nexus
        )
        #expect(FileManager.default.fileExists(atPath: folder.path))
        let cols = manager.pageCollections(in: pageType)
        #expect(cols.count == 1)
        #expect(cols.first?.title == "Tasks")
    }

    @Test("renamePageType renames folder + updates collection paths")
    func renamePageType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createPageType(name: "Planner", icon: nil)
        let pageType = manager.types.first!
        try await manager.createPageCollection(name: "Tasks", inPageType: pageType)

        try await manager.renamePageType(pageType, to: "Schedule")
        let newFolder = NexusPaths.vaultFolderURL(forTitle: "Schedule", in: nexus)
        #expect(FileManager.default.fileExists(atPath: newFolder.path))
        // PageCollection still present under new PageType folder
        let renamedType = manager.types.first!
        let cols = manager.pageCollections(in: renamedType)
        #expect(cols.count == 1)
        #expect(cols.first?.title == "Tasks")
    }

    @Test("deletePageType removes folder + collections")
    func deletePageType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createPageType(name: "Planner", icon: nil)
        let pageType = manager.types.first!
        try await manager.createPageCollection(name: "Tasks", inPageType: pageType)

        try await manager.deletePageType(pageType)
        let folder = NexusPaths.vaultFolderURL(forTitle: "Planner", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(manager.types.isEmpty)

        // Folder now in .trash, preserving relative path under nexus root
        // (PageType folder lives inside <nexus>/Pages/ post-ParadigmV2 Phase 6).
        let trashFolder = NexusPaths.trashDir(in: nexus).appendingPathComponent("Pages/Planner")
        #expect(FileManager.default.fileExists(atPath: trashFolder.path))
    }

    @Test("loadAll skips folders inside Pages/ without _schema.json (cosmetic dirs)")
    func skipCosmeticFolders() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Cosmetic folder inside the Pages/ wrapper that ISN'T a PageType
        // (no _schema.json sidecar). Plus a legacy-shaped folder at the nexus
        // root, which the wrapper-scoped scan never visits.
        let pagesWrapper = NexusPaths.pagesWrapperDir(in: nexus.rootURL)
        try FileManager.default.createDirectory(at: pagesWrapper, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: pagesWrapper.appendingPathComponent("NotAVault", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: nexus.rootURL.appendingPathComponent("LegacyRoot", isDirectory: true),
            withIntermediateDirectories: true
        )
        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()
        #expect(manager.types.isEmpty)
    }

    @Test("renamePageCollection moves the folder")
    func renamePageCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()
        try await manager.createPageType(name: "Planner", icon: nil)
        let pageType = manager.types.first!
        try await manager.createPageCollection(name: "Tasks", inPageType: pageType)
        let coll = manager.pageCollections(in: pageType).first!

        try await manager.renamePageCollection(coll, to: "To-dos")
        let newFolder = NexusPaths.collectionFolderURL(
            forTitle: "To-dos", inVaultTitled: "Planner", in: nexus
        )
        #expect(FileManager.default.fileExists(atPath: newFolder.path))
        #expect(manager.pageCollections(in: pageType).first?.title == "To-dos")
    }

    @Test("deletePageCollection removes folder")
    func deletePageCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()
        try await manager.createPageType(name: "Planner", icon: nil)
        let pageType = manager.types.first!
        try await manager.createPageCollection(name: "Tasks", inPageType: pageType)
        let coll = manager.pageCollections(in: pageType).first!

        try await manager.deletePageCollection(coll)
        let folder = NexusPaths.collectionFolderURL(
            forTitle: "Tasks", inVaultTitled: "Planner", in: nexus
        )
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(manager.pageCollections(in: pageType).isEmpty)

        // Folder now in .trash, preserving relative path under nexus root
        // (PageCollection folder lives inside <nexus>/Pages/<Type>/ post-ParadigmV2 Phase 6).
        let trashFolder = NexusPaths.trashDir(in: nexus)
            .appendingPathComponent("Pages/Planner/Tasks")
        #expect(FileManager.default.fileExists(atPath: trashFolder.path))
    }
}
