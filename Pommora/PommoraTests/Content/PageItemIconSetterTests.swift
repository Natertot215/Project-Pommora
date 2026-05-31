//
//  PageItemIconSetterTests.swift
//  PommoraTests
//
//  TDD — RED step. Tests that updatePageIcon / updateItemIcon persist the icon
//  to the entity's file on disk (Page .md frontmatter / Item .json). All four
//  tests FAIL until the GREEN step wires the real bodies (the stubs are no-ops,
//  so the icon stays nil ≠ the chosen symbol).
//
//  Struct name MATCHES the filename so `-only-testing:PommoraTests/PageItemIconSetterTests`
//  resolves correctly (quirk #17).
//
//  Setup mirrors PageContentManagerUpdatePageTests + NewItemSheetTests: build the
//  Type + Collection on disk directly, then drive the content manager's create CRUD
//  so the entity file exists and the in-memory cache is populated.
//

import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("PageItemIconSetterTests")
struct PageItemIconSetterTests {

    // MARK: - Test 1: Page at Type root

    @Test func updatePageIconPersistsToDisk_typeRoot() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let (vault, _, manager) = try await makePageSetup(nexus: nexus)
        try await manager.createPage(name: "RootNotes", inVaultRoot: vault)
        let page = manager.pages(in: vault).first!

        // Act — stub is a no-op; real body lands in the GREEN step.
        try await manager.updatePageIcon(page, to: "star.fill", vault: vault, collection: nil)

        // On-disk assertion: reload the .md frontmatter directly.
        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.frontmatter.icon == "star.fill")
    }

    // MARK: - Test 2: Item at Type root

    @Test func updateItemIconPersistsToDisk_typeRoot() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let (type, manager) = try await makeItemSetup(nexus: nexus)
        let item = try await manager.createItem(name: "Quick", inTypeRoot: type)

        // Act — stub is a no-op; real body lands in the GREEN step.
        try await manager.updateItemIcon(item, to: "bolt.fill", type: type, collection: nil)

        // On-disk assertion: reload the .json directly.
        let url = NexusPaths.itemFileURL(forTitle: item.title, in: folderURL(for: type, nexus: nexus))
        let reloaded = try Item.load(from: url)
        #expect(reloaded.icon == "bolt.fill")
    }

    // MARK: - Test 3: Page inside a PageCollection

    @Test func updatePageIconPersistsToDisk_inCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let (vault, coll, manager) = try await makePageSetup(nexus: nexus)
        try await manager.createPage(name: "Notes", in: coll, vault: vault)
        let page = manager.pages(in: coll).first!

        // Act — stub is a no-op; real body lands in the GREEN step.
        try await manager.updatePageIcon(page, to: "star.fill", vault: vault, collection: coll)

        let reloaded = try PageFile.load(from: page.url)
        #expect(reloaded.frontmatter.icon == "star.fill")
    }

    // MARK: - Test 4: Item inside an ItemCollection

    @Test func updateItemIconPersistsToDisk_inCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let (type, manager) = try await makeItemSetup(nexus: nexus)
        let coll = try makeItemCollection(nexus: nexus, title: "Mains", in: type)
        let item = try await manager.createItem(name: "Pasta", in: coll, type: type)

        // Act — stub is a no-op; real body lands in the GREEN step.
        try await manager.updateItemIcon(item, to: "bolt.fill", type: type, collection: coll)

        let url = NexusPaths.itemFileURL(forTitle: item.title, in: coll.folderURL)
        let reloaded = try Item.load(from: url)
        #expect(reloaded.icon == "bolt.fill")
    }

    // MARK: - Helpers

    /// Builds a PageType + a PageCollection on disk and a PageContentManager
    /// (mirrors PageContentManagerUpdatePageTests.setup).
    private func makePageSetup(nexus: Nexus) async throws
        -> (PageType, PageCollection, PageContentManager)
    {
        let vault = PageType(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: "V", in: nexus))

        let collFolder = NexusPaths.collectionFolderURL(forTitle: "C", inVaultTitled: "V", in: nexus)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = PageCollection(
            id: ULID.generate(),
            typeID: vault.id,
            title: "C",
            folderURL: collFolder,
            modifiedAt: Date()
        )

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (vault, coll, manager)
    }

    /// Builds an ItemType on disk and an ItemContentManager
    /// (mirrors NewItemSheetTests.makeItemType).
    private func makeItemSetup(nexus: Nexus) async throws -> (ItemType, ItemContentManager) {
        let type = ItemType(
            id: ULID.generate(), title: "Recipes", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "Recipes")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try type.save(to: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "Recipes"))

        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (type, manager)
    }

    @discardableResult
    private func makeItemCollection(nexus: Nexus, title: String, in itemType: ItemType) throws
        -> ItemCollection
    {
        let folderURL = NexusPaths.itemCollectionFolderURL(
            in: nexus.rootURL,
            typeFolderName: itemType.title,
            collectionFolderName: title
        )
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let coll = ItemCollection(
            id: ULID.generate(),
            typeID: itemType.id,
            title: title,
            folderURL: folderURL,
            modifiedAt: Date()
        )
        try coll.save(to: folderURL.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename))
        return coll
    }

    /// Type-root folder URL for an ItemType (matches ItemContentManager's
    /// `folderURL(for:)` derivation used by createItem(inTypeRoot:)).
    private func folderURL(for itemType: ItemType, nexus: Nexus) -> URL {
        NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: itemType.title)
    }
}
