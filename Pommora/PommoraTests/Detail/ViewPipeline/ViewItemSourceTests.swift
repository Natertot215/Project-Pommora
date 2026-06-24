//
//  ViewItemSourceTests.swift
//  PommoraTests
//
//  Verifies ViewItemSource's parent + setLabel stamping in both scopes. Uses a
//  TempNexus + real managers (the source reads the live page caches), mirroring
//  the hand-built Collection/Collection/Set fixtures in PageSetContentTests.
//

import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("ViewItemSourceTests")
struct ViewItemSourceTests {

    // MARK: - Collection scope

    @Test("vault scope stamps every parent kind + setLabel only on set pages")
    func collectionScopeStampsParentsAndSetLabels() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let collection = try makePageCollection(nexus: nexus, title: "Notes")
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: collection)
        let set = try makePageSet(title: "Drafts", in: coll)

        let collectionFolder = NexusPaths.collectionFolderURL(forTitle: collection.title, in: nexus)
        _ = try writePage(titled: "RootPage", in: collectionFolder)
        _ = try writePage(titled: "CollPage", in: coll.folderURL)
        _ = try writePage(titled: "SetPage", in: set.folderURL)

        let (content, sets) = managers(nexus: nexus)
        await content.loadAll(for: collection)
        await content.loadAll(forCollection: coll)
        await content.loadAll(for: set)
        await sets.loadAll(types: [collection])

        let items = ViewItemSource.items(
            for: .pageCollection(collection),
            content: content,
            sets: sets,
            collections: { _ in [coll] }
        )

        let byTitle = Dictionary(uniqueKeysWithValues: items.map { ($0.page.title, $0) })

        // Collection-root page.
        let root = try #require(byTitle["RootPage"])
        guard case .collectionRoot = root.parent else { return #expect(Bool(false), "expected collectionRoot") }
        #expect(root.setLabel == nil)

        // Collection-loose page.
        let collPage = try #require(byTitle["CollPage"])
        guard case .collection(let c, _) = collPage.parent else {
            return #expect(Bool(false), "expected collection")
        }
        #expect(c.id == coll.id)
        #expect(collPage.setLabel == nil)

        // Set page — carries the set label as its gallery chip.
        let setPage = try #require(byTitle["SetPage"])
        guard case .set(let s, let sc, _) = setPage.parent else {
            return #expect(Bool(false), "expected set")
        }
        #expect(s.id == set.id)
        #expect(sc.id == coll.id)
        #expect(setPage.setLabel == "Drafts")
    }

    // MARK: - Collection scope

    @Test("collection scope stamps root + set parents, never a setLabel")
    func collectionScopeStampsParentsNoLabel() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let collection = try makePageCollection(nexus: nexus, title: "Notes")
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: collection)
        let set = try makePageSet(title: "Drafts", in: coll)

        _ = try writePage(titled: "CollPage", in: coll.folderURL)
        _ = try writePage(titled: "SetPage", in: set.folderURL)

        let (content, sets) = managers(nexus: nexus)
        await content.loadAll(forCollection: coll)
        await content.loadAll(for: set)
        await sets.loadAll(types: [collection])

        let items = ViewItemSource.items(
            for: .collection(coll, pageCollection: collection),
            content: content,
            sets: sets,
            collections: { _ in [coll] }
        )

        let byTitle = Dictionary(uniqueKeysWithValues: items.map { ($0.page.title, $0) })

        let collPage = try #require(byTitle["CollPage"])
        guard case .collection(let c, _) = collPage.parent else {
            return #expect(Bool(false), "expected collection")
        }
        #expect(c.id == coll.id)
        #expect(collPage.setLabel == nil)

        let setPage = try #require(byTitle["SetPage"])
        guard case .set(let s, _, _) = setPage.parent else {
            return #expect(Bool(false), "expected set")
        }
        #expect(s.id == set.id)
        // Collection scope carries no gallery chip label.
        #expect(setPage.setLabel == nil)
    }

    // MARK: - Helpers

    private func managers(nexus: Nexus) -> (PageContentManager, PageSetManager) {
        let content = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        let sets = PageSetManager(nexus: nexus)
        return (content, sets)
    }

    @discardableResult
    private func makePageCollection(nexus: Nexus, title: String) throws -> PageCollection {
        let collection = PageCollection(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folderURL = NexusPaths.collectionFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try collection.save(to: NexusPaths.collectionMetadataURL(forTitle: title, in: nexus))
        return collection
    }

    @discardableResult
    private func makePageCollection(
        nexus: Nexus, title: String, in pageCollection: PageCollection
    ) throws
        -> PageSet
    {
        let folderURL = NexusPaths.setFolderURL(
            forTitle: title, inCollectionTitled: pageCollection.title, in: nexus)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let coll = PageSet(
            id: ULID.generate(), parentID: pageCollection.id, title: title,
            folderURL: folderURL, modifiedAt: Date()
        )
        try coll.save(to: folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        return coll
    }

    @discardableResult
    private func makePageSet(title: String, in collection: PageSet) throws -> PageSet {
        let folderURL = collection.folderURL.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let set = PageSet(
            id: ULID.generate(), parentID: collection.id, title: title,
            folderURL: folderURL, modifiedAt: Date()
        )
        try set.save(to: folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        return set
    }

    @discardableResult
    private func writePage(titled title: String, in folder: URL) throws -> String {
        let id = ULID.generate()
        let fm = PageFrontmatter(
            id: id, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date()
        )
        try AtomicYAMLMarkdown.write(
            frontmatter: fm, body: "",
            to: NexusPaths.pageFileURL(forTitle: title, in: folder))
        return id
    }
}
