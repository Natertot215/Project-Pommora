//
//  CollectionTypeIDReconcileTests.swift
//  PommoraTests
//
//  RED baseline (failing until the fix lands).
//
//  Bug pinned: a PageCollection / ItemCollection lives in a sub-folder inside
//  its parent Type folder and carries a `type_id` in its sidecar. After a Type
//  (vault) re-adoption the Type can mint a NEW `id`, while the collection's
//  stored `type_id` keeps pointing at the OLD (now-vanished) Type id — so
//  property / schema resolution finds nothing (empty "Edit Properties" pane).
//
//  Intended fix (NOT yet implemented): PageTypeManager.loadAll() and
//  ItemTypeManager.loadAll() must reconcile each collection's `type_id` to its
//  CONTAINING Type's `id` (the folder is authoritative) — both IN MEMORY and by
//  re-saving the sidecar to disk. These tests assert that reconcile and will
//  FAIL until loadAll learns to do it.
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
        let pageType = PageType(
            id: vaultID,
            title: vaultName,
            icon: nil,
            properties: [],
            views: [],
            modifiedAt: Date()
        )
        try pageType.save(to: vaultFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))

        // Collection sub-folder whose sidecar `type_id` = wrongTypeID (drift).
        let collName = "Drifted Collection"
        let collFolder = vaultFolder.appendingPathComponent(collName, isDirectory: true)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let collMetaURL = collFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        let drifted = PageCollection(
            id: ULID.generate(),
            typeID: wrongTypeID,  // <- points at the vanished old vault id
            title: collName,
            folderURL: collFolder,
            modifiedAt: Date()
        )
        try drifted.save(to: collMetaURL)

        // Load. No index wired — reconcile is about type_id, not the SQLite index.
        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()

        // Resolve the loaded vault by title so we hand the right PageType to
        // pageCollections(in:).
        let loadedVault = try #require(manager.types.first(where: { $0.title == vaultName }))
        #expect(loadedVault.id == vaultID)

        // (a) IN MEMORY: the collection's typeID must be reconciled to V.
        let loadedColl = manager.pageCollections(in: loadedVault).first
        #expect(loadedColl?.typeID == vaultID)

        // (b) ON DISK: reloading the sidecar must also show V (re-saved).
        let reloaded = try PageCollection.load(from: collMetaURL)
        #expect(reloaded.typeID == vaultID)
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
        let pageType = PageType(
            id: vaultID, title: vaultName, icon: nil, properties: [], views: [], modifiedAt: Date()
        )
        try pageType.save(to: vaultFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))

        let collName = "Correct Collection"
        let collFolder = vaultFolder.appendingPathComponent(collName, isDirectory: true)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let collMetaURL = collFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        let correct = PageCollection(
            id: ULID.generate(),
            typeID: vaultID,  // already correct
            title: collName,
            folderURL: collFolder,
            modifiedAt: Date()
        )
        try correct.save(to: collMetaURL)

        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()

        let loadedVault = try #require(manager.types.first(where: { $0.title == vaultName }))
        #expect(manager.pageCollections(in: loadedVault).first?.typeID == vaultID)
        let reloaded = try PageCollection.load(from: collMetaURL)
        #expect(reloaded.typeID == vaultID)
    }

    // MARK: - Item side (symmetric)

    /// Items-side mirror: an ItemType folder whose `_itemtype.json` id = V,
    /// containing an ItemCollection sub-folder whose `_itemcollection.json`
    /// `type_id` is a DIFFERENT, wrong ULID. After loadAll the ItemCollection's
    /// `typeID` must become V both in memory and on disk.
    @Test func itemCollectionTypeIDReconcilesToContainingType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeID = ULID.generate()
        let wrongTypeID = ULID.generate()
        #expect(wrongTypeID != typeID)

        let typeName = "Re-adopted Type"
        let typeFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: typeName)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        let itemType = ItemType(
            id: typeID, title: typeName, icon: nil, properties: [], views: [], modifiedAt: Date()
        )
        try itemType.save(to: typeFolder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename))

        let collName = "Drifted Set"
        let collFolder = typeFolder.appendingPathComponent(collName, isDirectory: true)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let collMetaURL = collFolder.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename)
        let drifted = ItemCollection(
            id: ULID.generate(),
            typeID: wrongTypeID,  // <- points at the vanished old type id
            title: collName,
            folderURL: collFolder,
            modifiedAt: Date()
        )
        try drifted.save(to: collMetaURL)

        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        let loadedType = try #require(manager.types.first(where: { $0.title == typeName }))
        #expect(loadedType.id == typeID)

        // (a) IN MEMORY.
        let loadedColl = manager.itemCollections(in: loadedType).first
        #expect(loadedColl?.typeID == typeID)

        // (b) ON DISK.
        let reloaded = try ItemCollection.load(from: collMetaURL)
        #expect(reloaded.typeID == typeID)
    }

    /// Control / idempotence (Item side): a collection already pointing at V
    /// stays == V.
    @Test func itemCollectionAlreadyCorrectStaysCorrect() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeID = ULID.generate()
        let typeName = "Stable Type"
        let typeFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: typeName)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        let itemType = ItemType(
            id: typeID, title: typeName, icon: nil, properties: [], views: [], modifiedAt: Date()
        )
        try itemType.save(to: typeFolder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename))

        let collName = "Correct Set"
        let collFolder = typeFolder.appendingPathComponent(collName, isDirectory: true)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let collMetaURL = collFolder.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename)
        let correct = ItemCollection(
            id: ULID.generate(),
            typeID: typeID,  // already correct
            title: collName,
            folderURL: collFolder,
            modifiedAt: Date()
        )
        try correct.save(to: collMetaURL)

        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        let loadedType = try #require(manager.types.first(where: { $0.title == typeName }))
        #expect(manager.itemCollections(in: loadedType).first?.typeID == typeID)
        let reloaded = try ItemCollection.load(from: collMetaURL)
        #expect(reloaded.typeID == typeID)
    }
}
