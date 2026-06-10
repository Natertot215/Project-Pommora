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

    @Test("renamePageCollection preserves icon (cache + disk)")
    func renamePageCollectionPreservesOverrides() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()
        try await manager.createPageType(name: "Planner", icon: nil)
        let pageType = manager.types.first!
        try await manager.createPageCollection(name: "Tasks", inPageType: pageType)
        let coll = manager.pageCollections(in: pageType).first!

        try await manager.updatePageCollectionIcon(coll, to: "doc")
        let withIcon = manager.pageCollections(in: pageType).first!
        #expect(withIcon.icon == "doc")

        // Rename must NOT reset the icon.
        try await manager.renamePageCollection(withIcon, to: "To-dos")
        let renamed = manager.pageCollections(in: pageType).first!
        #expect(renamed.title == "To-dos")
        #expect(renamed.icon == "doc")

        // ...and it survives a reload-from-disk.
        let reloaded = PageTypeManager(nexus: nexus)
        await reloaded.loadAll()
        let fromDisk = reloaded.pageCollections(in: reloaded.types.first!).first!
        #expect(fromDisk.title == "To-dos")
        #expect(fromDisk.icon == "doc")
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

        // Capture whatever order the manager has settled on before the reorder.
        // Under the creation-order default the order is ULID-ascending, which
        // is non-deterministic when both ULIDs are generated within the same
        // millisecond. We therefore assert the DELTA (a specific item moved to
        // front) rather than hard-coding absolute positions.
        let before = manager.pageCollections(in: pageType)
        #expect(before.count == 2)
        let movedTitle = before[1].title  // the item we are about to move to front

        // Move index 1 to offset 0 (bring the second item to the front).
        manager.reorderPageCollections(in: pageType, fromOffsets: IndexSet(integer: 1), toOffset: 0)
        let after = manager.pageCollections(in: pageType).map(\.title)

        #expect(after != before.map(\.title))
        #expect(after.first == movedTitle)
        #expect(after.last == before[0].title)
    }
}
