//
//  CollectionIconTests.swift
//  PommoraTests
//
//  #45 (TDD). A per-Collection/Set icon must (1) round-trip through the sidecar
//  JSON (the source of truth) and (2) reach the SQLite index so the relation
//  picker's grouped query returns it. RED-first: these FAIL until `icon` is wired
//  into the model's Codable + the page_collections/item_collections schema + the
//  grouped query (the minimal stored field exists only so these compile).
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

    @Test func pageCollectionIconReachesGroupedQuery() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(index)

        let typeID = ULID.generate()
        try updater.upsertPageType(
            PageType(id: typeID, title: "Notes", icon: nil, properties: [], views: [], modifiedAt: Date()))
        let collID = ULID.generate()
        let collFolder = NexusPaths.vaultFolderURL(forTitle: "Notes", in: nexus)
            .appendingPathComponent("Daily", isDirectory: true)
        try updater.upsertPageCollection(
            PageCollection(
                id: collID, typeID: typeID, title: "Daily", folderURL: collFolder,
                modifiedAt: Date(), icon: "star"))
        // A member page so the collection group appears in the grouped result.
        let pageID = ULID.generate()
        let fm = PageFrontmatter(
            id: pageID, icon: nil, tier1: [], tier2: [], tier3: [], properties: [:], createdAt: Date())
        try updater.upsertPage(
            PageMeta(
                id: pageID, title: "Monday",
                url: nexus.rootURL.appendingPathComponent("Monday.md"), frontmatter: fm),
            pageTypeID: typeID, pageCollectionID: collID)

        let grouped = try await IndexQuery(index).entitiesByTargetGrouped(.pageType(typeID))
        let group = try #require(grouped.groups.first { $0.container.id == collID })
        #expect(group.container.icon == "star")
    }

    /// The icon must ALSO survive a full `IndexBuilder.populate` rebuild — the
    /// path a schema-version bump triggers. SQLite is regeneratable from the
    /// sidecars (architecture); a collection icon that only persists via
    /// incremental upsert but is dropped on rebuild is a real bug.
    @Test func pageCollectionIconSurvivesFullRebuild() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Seed a PageType ("Notes") + a PageCollection sub-folder ("Daily") with an icon.
        let pageTypeManager = PageTypeManager(nexus: nexus)
        await pageTypeManager.loadAll()
        try await pageTypeManager.createPageType(name: "Notes", icon: nil)
        let pt = pageTypeManager.types.first { $0.title == "Notes" }!
        let typeFolder = NexusPaths.vaultFolderURL(forTitle: "Notes", in: nexus)

        let collFolder = typeFolder.appendingPathComponent("Daily", isDirectory: true)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let collID = ULID.generate()
        try PageCollection(
            id: collID, typeID: pt.id, title: "Daily", folderURL: collFolder,
            modifiedAt: Date(), icon: "star"
        ).save(to: collFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))

        // A member page so the collection has content (realistic rebuild).
        let pageID = ULID.generate()
        let fm = PageFrontmatter(
            id: pageID, icon: nil, tier1: [], tier2: [], tier3: [], properties: [:], createdAt: Date())
        try AtomicYAMLMarkdown.write(
            frontmatter: fm, body: "", to: NexusPaths.pageFileURL(forTitle: "Monday", in: collFolder))

        // Full rebuild from disk.
        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus)

        let grouped = try await IndexQuery(idx).entitiesByTargetGrouped(.pageType(pt.id))
        let group = try #require(grouped.groups.first { $0.container.id == collID })
        #expect(group.container.icon == "star")
    }
}
