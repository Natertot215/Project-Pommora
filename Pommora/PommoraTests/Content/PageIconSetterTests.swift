//
//  PageIconSetterTests.swift
//  PommoraTests
//
//  Tests that updatePageIcon persists the icon to the Page's .md frontmatter
//  on disk, at the Type root and inside a PageSet.
//
//  Struct name MATCHES the filename so `-only-testing:PommoraTests/PageIconSetterTests`
//  resolves correctly (quirk #17).
//
//  Setup mirrors PageContentManagerUpdatePageTests: build the Type + Collection
//  on disk directly, then drive the content manager's create CRUD so the entity
//  file exists and the in-memory cache is populated.
//

import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("PageIconSetterTests")
struct PageIconSetterTests {

    // MARK: - Test 1: Page at Type root

    @Test func updatePageIconPersistsToDisk_typeRoot() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let (collection, _, manager) = try await makePageSetup(nexus: nexus)
        try await manager.createPage(name: "RootNotes", inCollectionRoot: collection)
        let page = manager.pages(in: collection).first!

        try await manager.updatePageIcon(page, to: "star.fill", pageCollection: collection, collection: nil)

        // On-disk assertion: reload the .md frontmatter directly.
        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.frontmatter.icon == "star.fill")
    }

    // MARK: - Test 2: Page inside a PageSet

    @Test func updatePageIconPersistsToDisk_inCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let (collection, coll, manager) = try await makePageSetup(nexus: nexus)
        try await manager.createPage(name: "Notes", in: coll, pageCollection: collection)
        let page = manager.pages(inCollection: coll).first!

        try await manager.updatePageIcon(page, to: "star.fill", pageCollection: collection, collection: coll)

        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.frontmatter.icon == "star.fill")
    }

    // MARK: - Helpers

    /// Builds a PageCollection + a PageSet on disk and a PageContentManager
    /// (mirrors PageContentManagerUpdatePageTests.setup).
    private func makePageSetup(nexus: Nexus) async throws
        -> (PageCollection, PageSet, PageContentManager)
    {
        let collection = PageCollection(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        let collectionFolder = NexusPaths.collectionFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: collectionFolder, withIntermediateDirectories: true)
        try collection.save(to: NexusPaths.collectionMetadataURL(forTitle: "V", in: nexus))

        let collFolder = NexusPaths.setFolderURL(forTitle: "C", inCollectionTitled: "V", in: nexus)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = PageSet(
            id: ULID.generate(),
            parentID: collection.id,
            title: "C",
            folderURL: collFolder,
            modifiedAt: Date()
        )

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (collection, coll, manager)
    }
}
