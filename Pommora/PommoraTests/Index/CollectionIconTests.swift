//
//  CollectionIconTests.swift
//  PommoraTests
//
//  #45 (TDD). A per-Collection/Set icon must round-trip through the sidecar
//  JSON (the source of truth). The grouped-query assertions (pageType-scoped
//  entitiesByContextTargetGrouped) are removed: post-Relations-redesign, grouped
//  queries are tier-only and the .pageType case no longer exists.
//
//  Struct name MATCHES the filename (quirk #18).
//

import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("CollectionIconTests")
struct CollectionIconTests {

    @Test func pageCollectionIconRoundTripsThroughSidecar() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.vaultFolderURL(forTitle: "Notes", in: nexus)
            .appendingPathComponent("Daily", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)

        let coll = PageCollection(
            id: ULID.generate(), typeID: ULID.generate(), title: "Daily",
            folderURL: folder, modifiedAt: Date(), icon: "star")
        try coll.save(to: url)
        let loaded = try PageCollection.load(from: url)

        #expect(loaded.icon == "star")
    }

    @Test func itemCollectionIconRoundTripsThroughSidecar() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "Books")
            .appendingPathComponent("Mains", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename)

        let coll = ItemCollection(
            id: ULID.generate(), typeID: ULID.generate(), title: "Mains",
            folderURL: folder, modifiedAt: Date(), icon: "fork.knife")
        try coll.save(to: url)
        let loaded = try ItemCollection.load(from: url)

        #expect(loaded.icon == "fork.knife")
    }
}
