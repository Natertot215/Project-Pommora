import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("PageTypeManager")
struct PageTypeManagerTests {

    @Test("createPageType writes folder + _pagetype.json")
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
        // (flatlayout: PageType folder lives directly at the nexus root).
        let trashFolder = NexusPaths.trashDir(in: nexus).appendingPathComponent("Planner")
        #expect(FileManager.default.fileExists(atPath: trashFolder.path))
    }

    @Test("loadAll skips root folders without _pagetype.json (cosmetic dirs)")
    func skipCosmeticFolders() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Cosmetic folder at the nexus root that ISN'T a PageType (no
        // `_pagetype.json` sidecar). Discovery filters by sidecar presence, so
        // it never resolves into the loaded types.
        try FileManager.default.createDirectory(
            at: nexus.rootURL.appendingPathComponent("NotAVault", isDirectory: true),
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
        // (flatlayout: PageCollection folder lives inside <nexus>/<Type>/).
        let trashFolder = NexusPaths.trashDir(in: nexus)
            .appendingPathComponent("Planner/Tasks")
        #expect(FileManager.default.fileExists(atPath: trashFolder.path))
    }

    @Test("reorderPageCollections swaps order in the manager")
    func reorderPageCollections() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()
        try await manager.createPageType(name: "Planner", icon: nil)
        let pageType = manager.types.first!
        try await manager.createPageCollection(name: "Alpha", inPageType: pageType)
        try await manager.createPageCollection(name: "Beta", inPageType: pageType)

        let before = manager.pageCollections(in: pageType).map(\.title)
        // move Beta (index 1) above Alpha (index 0)
        manager.reorderPageCollections(in: pageType, fromOffsets: IndexSet(integer: 1), toOffset: 0)
        let after = manager.pageCollections(in: pageType).map(\.title)

        #expect(before != after)
        #expect(after.first == "Beta")
        #expect(after.last == "Alpha")
    }
}
