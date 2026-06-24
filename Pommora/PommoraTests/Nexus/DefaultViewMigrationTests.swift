//
//  DefaultViewMigrationTests.swift
//  PommoraTests
//
//  Regression coverage for Task 5 (Phase A — v0.3.1): loadAll on
//  PageCollectionManager mints a default Table view for any Type or Collection
//  whose `views` array is empty. Mirrors the LoadAllIndexSyncTests pattern
//  (quirk #15) — same defensive-on-load contract.
//

import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("loadAll mints default views when missing")
struct DefaultViewMigrationTests {

    // MARK: - PageCollection + PageSet

    @Test func pageTypeWithoutViewsGetsDefaultTableView() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // PageCollection written to disk with views = [] (matches pre-v0.3.1 sidecars).
        let vaultID = ULID.generate()
        let folder = NexusPaths.vaultFolderURL(forTitle: "Books", in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pc = PageCollection(
            id: vaultID,
            title: "Books",
            icon: nil,
            properties: [
                PropertyDefinition(id: "prop_01HA", name: "Author", type: .multiSelect),
                PropertyDefinition(id: "prop_01HB", name: "Year", type: .number),
            ],
            views: [],
            modifiedAt: Date()
        )
        let sidecarURL = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        try pc.save(to: sidecarURL)

        let manager = PageCollectionManager(nexus: nexus)
        await manager.loadAll()

        #expect(manager.types.count == 1)
        let loaded = manager.types[0]
        #expect(loaded.views.count == 1)
        #expect(loaded.views[0].type == .table)
        #expect(loaded.views[0].name == "Table")
        #expect(loaded.views[0].propertyOrder == ["_title", "prop_01HA", "prop_01HB"])

        // Re-decode the sidecar from disk — the migration must persist, not
        // just exist in memory.
        let reloaded = try PageCollection.load(from: sidecarURL)
        #expect(reloaded.views.count == 1)
        #expect(reloaded.views[0].id == loaded.views[0].id)
    }

    @Test func pageTypeWithExistingViewsIsLeftAlone() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vaultID = ULID.generate()
        let folder = NexusPaths.vaultFolderURL(forTitle: "Notes", in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let existing = SavedView(
            id: "view_01HEXISTING",
            name: "My View",
            icon: "star",
            type: .table,
            propertyOrder: ["_title", "prop_only"],
            hiddenProperties: []
        )
        let pc = PageCollection(
            id: vaultID,
            title: "Notes",
            icon: nil,
            properties: [],
            views: [existing],
            modifiedAt: Date()
        )
        try pc.save(to:folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))

        let manager = PageCollectionManager(nexus: nexus)
        await manager.loadAll()

        #expect(manager.types[0].views.count == 1)
        #expect(manager.types[0].views[0].id == "view_01HEXISTING")
        #expect(manager.types[0].views[0].name == "My View")
    }

    @Test func pageCollectionWithoutViewsGetsDefaultTableView() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vaultID = ULID.generate()
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: "Drafts", in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        let pc = PageCollection(
            id: vaultID,
            title: "Drafts",
            icon: nil,
            properties: [PropertyDefinition(id: "prop_01HSTATUS", name: "Stage", type: .status)],
            views: [],
            modifiedAt: Date()
        )
        try pc.save(to:vaultFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))

        let collID = ULID.generate()
        let collFolder = vaultFolder.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let collection = PageSet(
            id: collID,
            parentID: vaultID,
            title: "Inbox",
            folderURL: collFolder,
            modifiedAt: Date()
        )
        let collSidecar = collFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        try collection.save(to: collSidecar)

        let manager = PageCollectionManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageTypeProvider = { [weak manager] in manager?.types ?? [] }
        manager.pageSetManager = setManager
        await manager.loadAll()
        await setManager.loadAll(types: manager.types)

        let loadedColl = try #require(manager.pageCollectionsByType[vaultID]?.first)
        #expect(loadedColl.views.count == 1)
        #expect(loadedColl.views[0].type == .table)
        // Collection inherits parent's property IDs as the starting visible
        // ordering — locked decision.
        #expect(loadedColl.views[0].propertyOrder == ["_title", "prop_01HSTATUS"])

        // Persisted, not just in-memory.
        let reloaded = try PageSet.load(from: collSidecar)
        #expect(reloaded.views.count == 1)
    }

    // MARK: - Idempotency

    @Test func loadAllTwiceDoesNotReMint() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vaultID = ULID.generate()
        let folder = NexusPaths.vaultFolderURL(forTitle: "Vault", in: nexus)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pc = PageCollection(
            id: vaultID, title: "Vault", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        try pc.save(to:folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))

        let manager = PageCollectionManager(nexus: nexus)
        await manager.loadAll()
        let firstViewID = manager.types[0].views[0].id

        // Second pass — must NOT mint a new view (would change the id).
        await manager.loadAll()
        #expect(manager.types[0].views.count == 1)
        #expect(manager.types[0].views[0].id == firstViewID)
    }
}
