//
//  CollectionTypeIDReconcileTests.swift
//  PommoraTests
//
//  RED baseline (failing until the fix lands).
//
//  Bug pinned: a PageSet lives in a sub-folder inside its parent Type
//  folder and carries a `type_id` in its sidecar. After a Type (collection)
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

    /// On disk: a collection folder whose `_pagetype.json` id = V, containing a
    /// collection sub-folder whose `_pagecollection.json` `type_id` points at a
    /// DIFFERENT, wrong ULID (the drift). After loadAll, the folder is
    /// authoritative — the collection's `collectionID` must become V both in memory
    /// and on disk.
    @Test func pageCollectionCollectionIDReconcilesToContainingCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Fresh collection id (V) — what the collection SHOULD point at.
        let collectionID = ULID.generate()
        // A different, stale id — the drift left over from a prior adoption.
        let wrongCollectionID = ULID.generate()
        #expect(wrongCollectionID != collectionID)

        let collectionName = "Re-adopted Vault"
        let collectionFolder = NexusPaths.collectionFolderURL(forTitle: collectionName, in: nexus)
        try FileManager.default.createDirectory(at: collectionFolder, withIntermediateDirectories: true)
        let pc = PageCollection(
            id: collectionID,
            title: collectionName,
            icon: nil,
            properties: [],
            views: [],
            modifiedAt: Date()
        )
        try pc.save(to: collectionFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))

        // Collection sub-folder whose sidecar `type_id` = wrongCollectionID (drift).
        let collName = "Drifted Collection"
        let collFolder = collectionFolder.appendingPathComponent(collName, isDirectory: true)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let collMetaURL = collFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
        let drifted = PageSet(
            id: ULID.generate(),
            parentID: wrongCollectionID,  // <- points at the vanished old collection id
            title: collName,
            folderURL: collFolder,
            modifiedAt: Date()
        )
        try drifted.save(to: collMetaURL)

        // Load. No index wired — reconcile is about type_id, not the SQLite index.
        let manager = PageCollectionManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageCollectionProvider = { [weak manager] in manager?.types ?? [] }
        manager.pageSetManager = setManager
        await manager.loadAll()
        await setManager.loadAll(types: manager.types)

        // Resolve the loaded collection by title so we hand the right PageCollection to
        // pageCollections(in:).
        let loadedCollection = try #require(manager.types.first(where: { $0.title == collectionName }))
        #expect(loadedCollection.id == collectionID)

        // (a) IN MEMORY: the collection's collectionID must be reconciled to V.
        let loadedColl = manager.pageCollections(in: loadedCollection).first
        #expect(loadedColl?.parentID == collectionID)

        // (b) ON DISK: reloading the sidecar must also show V (re-saved).
        let reloaded = try PageSet.load(from: collMetaURL)
        #expect(reloaded.parentID == collectionID)
    }

    /// Control / idempotence: a second collection whose `type_id` already == V
    /// must stay == V after loadAll (no spurious rewrite to a wrong value).
    @Test func pageCollectionAlreadyCorrectStaysCorrect() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let collectionID = ULID.generate()
        let collectionName = "Stable Vault"
        let collectionFolder = NexusPaths.collectionFolderURL(forTitle: collectionName, in: nexus)
        try FileManager.default.createDirectory(at: collectionFolder, withIntermediateDirectories: true)
        let pc = PageCollection(
            id: collectionID, title: collectionName, icon: nil, properties: [], views: [], modifiedAt: Date()
        )
        try pc.save(to: collectionFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))

        let collName = "Correct Collection"
        let collFolder = collectionFolder.appendingPathComponent(collName, isDirectory: true)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let collMetaURL = collFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
        let correct = PageSet(
            id: ULID.generate(),
            parentID: collectionID,  // already correct
            title: collName,
            folderURL: collFolder,
            modifiedAt: Date()
        )
        try correct.save(to: collMetaURL)

        let manager = PageCollectionManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageCollectionProvider = { [weak manager] in manager?.types ?? [] }
        manager.pageSetManager = setManager
        await manager.loadAll()
        await setManager.loadAll(types: manager.types)

        let loadedCollection = try #require(manager.types.first(where: { $0.title == collectionName }))
        #expect(manager.pageCollections(in: loadedCollection).first?.parentID == collectionID)
        let reloaded = try PageSet.load(from: collMetaURL)
        #expect(reloaded.parentID == collectionID)
    }

}
