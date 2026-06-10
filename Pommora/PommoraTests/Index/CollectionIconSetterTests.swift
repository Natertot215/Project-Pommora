//
//  CollectionIconSetterTests.swift
//  PommoraTests
//
//  F1. Tests that updatePageCollectionIcon persists the icon to the sidecar
//  on disk and syncs the in-memory collection array.
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
}
