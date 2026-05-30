//
//  CollectionIconSetterTests.swift
//  PommoraTests
//
//  F1 (TDD — RED step). Tests that updatePageCollectionIcon / updateItemCollectionIcon
//  persist the icon to the sidecar on disk and sync the in-memory collection array.
//  Both tests FAIL until the GREEN step wires the real bodies.
//
//  Struct name MATCHES the filename so `-only-testing:PommoraTests/CollectionIconSetterTests`
//  resolves correctly (quirk #17).
//

import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("CollectionIconSetterTests")
struct CollectionIconSetterTests {

    @Test func updatePageCollectionIconPersistsToDiskAndMemory() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Build a PageType + PageCollection via normal CRUD so
        // pageCollectionsByType is populated and the sidecar exists on disk.
        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()
        try await manager.createPageType(name: "Notes", icon: nil)
        let pageType = manager.types.first!
        try await manager.createPageCollection(name: "Daily", inPageType: pageType)
        let collection = manager.pageCollections(in: pageType).first!

        // Act — stub is a no-op; real body lands in the GREEN step.
        try await manager.updatePageCollectionIcon(collection, to: "star.fill")

        // --- In-memory assertion ---
        let inMemory = manager.pageCollections(in: pageType).first { $0.id == collection.id }
        #expect(inMemory?.icon == "star.fill")

        // --- On-disk assertion: reload sidecar directly ---
        let sidecarURL = collection.folderURL
            .appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        let reloaded = try PageCollection.load(from: sidecarURL)
        #expect(reloaded.icon == "star.fill")
    }

    @Test func updateItemCollectionIconPersistsToDiskAndMemory() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Build an ItemType + ItemCollection via normal CRUD.
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()
        try await manager.createItemType(name: "Books", icon: nil)
        let itemType = manager.types.first!
        try await manager.createItemCollection(name: "Mains", inItemType: itemType)
        let collection = manager.itemCollections(in: itemType).first!

        // Act — stub is a no-op; real body lands in the GREEN step.
        try await manager.updateItemCollectionIcon(collection, to: "star.fill")

        // --- In-memory assertion ---
        let inMemory = manager.itemCollections(in: itemType).first { $0.id == collection.id }
        #expect(inMemory?.icon == "star.fill")

        // --- On-disk assertion: reload sidecar directly ---
        let sidecarURL = collection.folderURL
            .appendingPathComponent(NexusPaths.itemCollectionSidecarFilename)
        let reloaded = try ItemCollection.load(from: sidecarURL)
        #expect(reloaded.icon == "star.fill")
    }
}
