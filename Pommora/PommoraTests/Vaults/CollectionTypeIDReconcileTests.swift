//
//  CollectionTypeIDReconcileTests.swift
//  PommoraTests
//
//  RED baseline (failing until the fix lands).
//
//  Bug pinned: a PageSet lives in a sub-folder inside its parent Type
//  folder and carries a `type_id` in its sidecar. After a Type (vault)
//  re-adoption the Type can mint a NEW `id`, while the collection's stored
//  `type_id` keeps pointing at the OLD (now-vanished) Type id — so property /
//  schema resolution finds nothing (empty "Edit Properties" pane).
//
//  Fix under test: PageCollectionManager.loadAll() must reconcile each collection's
//  `type_id` to its CONTAINING Type's `id` (the folder is authoritative) —
//  both IN MEMORY and by re-saving the sidecar to disk.
//

import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("Collection type_id reconciles to its containing Type on loadAll")
struct CollectionTypeIDReconcileTests {

    // MARK: - Page side

    /// On disk: a vault folder whose `_pagetype.json` id = V, containing a
    /// collection sub-folder whose `_pagecollection.json` `type_id` points at a
    /// DIFFERENT, wrong ULID (the drift). After loadAll, the folder is
    /// authoritative — the collection's `typeID` must become V both in memory
    /// and on disk.
    @Test func pageCollectionTypeIDReconcilesToContainingVault() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Fresh vault id (V) — what the collection SHOULD point at.
        let vaultID = ULID.generate()
        // A different, stale id — the drift left over from a prior adoption.
        let wrongTypeID = ULID.generate()
        #expect(wrongTypeID != vaultID)

        let vaultName = "Re-adopted Vault"
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: vaultName, in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        let pc = PageCollection(
            id: vaultID,
            title: vaultName,
            icon: nil,
            properties: [],
            views: [],
            modifiedAt: Date()
        )
        try pc.save(to: vaultFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))

        // Collection sub-folder whose sidecar `type_id` = wrongTypeID (drift).
        let collName = "Drifted Collection"
        let collFolder = vaultFolder.appendingPathComponent(collName, isDirectory: true)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let collMetaURL = collFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
        let drifted = PageSet(
            id: ULID.generate(),
            parentID: wrongTypeID,  // <- points at the vanished old vault id
            title: collName,
            folderURL: collFolder,
            modifiedAt: Date()
        )
        try drifted.save(to: collMetaURL)

        // Load. No index wired — reconcile is about type_id, not the SQLite index.
        let manager = PageCollectionManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageTypeProvider = { [weak manager] in manager?.types ?? [] }
        manager.pageSetManager = setManager
        await manager.loadAll()
        await setManager.loadAll(types: manager.types)

        // Resolve the loaded vault by title so we hand the right PageCollection to
        // pageCollections(in:).
        let loadedVault = try #require(manager.types.first(where: { $0.title == vaultName }))
        #expect(loadedVault.id == vaultID)

        // (a) IN MEMORY: the collection's typeID must be reconciled to V.
        let loadedColl = manager.pageCollections(in: loadedVault).first
        #expect(loadedColl?.parentID == vaultID)

        // (b) ON DISK: reloading the sidecar must also show V (re-saved).
        let reloaded = try PageSet.load(from: collMetaURL)
        #expect(reloaded.parentID == vaultID)
    }

    /// Control / idempotence: a second collection whose `type_id` already == V
    /// must stay == V after loadAll (no spurious rewrite to a wrong value).
    @Test func pageCollectionAlreadyCorrectStaysCorrect() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vaultID = ULID.generate()
        let vaultName = "Stable Vault"
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: vaultName, in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        let pc = PageCollection(
            id: vaultID, title: vaultName, icon: nil, properties: [], views: [], modifiedAt: Date()
        )
        try pc.save(to: vaultFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))

        let collName = "Correct Collection"
        let collFolder = vaultFolder.appendingPathComponent(collName, isDirectory: true)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let collMetaURL = collFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
        let correct = PageSet(
            id: ULID.generate(),
            parentID: vaultID,  // already correct
            title: collName,
            folderURL: collFolder,
            modifiedAt: Date()
        )
        try correct.save(to: collMetaURL)

        let manager = PageCollectionManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageTypeProvider = { [weak manager] in manager?.types ?? [] }
        manager.pageSetManager = setManager
        await manager.loadAll()
        await setManager.loadAll(types: manager.types)

        let loadedVault = try #require(manager.types.first(where: { $0.title == vaultName }))
        #expect(manager.pageCollections(in: loadedVault).first?.parentID == vaultID)
        let reloaded = try PageSet.load(from: collMetaURL)
        #expect(reloaded.parentID == vaultID)
    }

}
