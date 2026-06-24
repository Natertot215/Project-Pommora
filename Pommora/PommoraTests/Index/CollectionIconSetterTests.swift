//
//  CollectionIconSetterTests.swift
//  PommoraTests
//
//  F1. Tests that updatePageSetIcon persists the icon to the sidecar
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

    @Test func updatePageSetIconPersistsToDiskAndMemory() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Build a PageType + PageSet via normal CRUD so
        // pageCollectionsByType is populated and the sidecar exists on disk.
        let manager = PageTypeManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageTypeProvider = { [weak manager] in manager?.types ?? [] }
        manager.pageSetManager = setManager
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
        let reloaded = try PageSet.load(from: sidecarURL)
        #expect(reloaded.icon == "star.fill")
    }
}
