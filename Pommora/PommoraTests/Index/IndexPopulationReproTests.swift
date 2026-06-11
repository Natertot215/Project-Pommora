//
//  IndexPopulationReproTests.swift
//  PommoraTests
//
//  REPRODUCTION tests (systematic debugging — reproduce before fixing) for the
//  twin runtime bug observed on a clean build:
//
//    (1) the inline tier picker shows NO Contexts —
//        `IndexQuery.entitiesByContextTarget(.contextTier(N))` returns empty even
//        though the user has Spaces/Topics;
//    (2) "SQLite error 19: FOREIGN KEY constraint failed - while executing
//        INSERT OR REPLACE INTO pages" when disclosing a Collection group.
//
//  Suspected root: a parent-entity sidecar that fails to decode is silently
//  skipped (`try?`) during loadAll / index population. Its child Pages then
//  FK-fail on `pages.page_collection_id` upsert, and skipped Spaces/Topics
//  never land in `contexts` so the tier picker reads empty.
//
//  Setup mirrors `PommoraTests/Nexus/LoadAllIndexSyncTests.swift` verbatim
//  (TempNexus + `PommoraIndex.open` + `IndexUpdater(index)` injected into each
//  manager + `manager.loadAll()`), plus the manager-construction shapes from
//  `SpaceManagerTests` / `TopicManagerTests` and the on-disk page seeding from
//  `Index/TierRelationsEmitTests` (`PageFile(...).save(to:)`).
//
//  Struct name MATCHES the filename (quirk #18 — Swift Testing filters by
//  suite/type name, not source filename).
//
//  These tests do NOT fix or touch production code. They characterize current
//  behavior so a fix can be validated against them.
//

import Foundation
import GRDB
import Testing

@testable import Pommora

@MainActor
@Suite("IndexPopulationReproTests")
struct IndexPopulationReproTests {

    // MARK: - Test A — clean-nexus structural population

    /// Isolates STRUCTURAL gaps. A fully VALID nexus (one Vault → one Page
    /// Collection → one Page; one Space at tier 1; one Topic at tier 2) is
    /// loaded through every manager in app order, all sharing one IndexUpdater
    /// over a fresh (schema-only, zero-row) index. If loadAll populates the
    /// index fully, the tier pickers see the Space + Topic and a page-property
    /// write does not FK-fail. If THIS fails, the bug is structural — loadAll
    /// itself doesn't fully populate the index.
    @Test func cleanNexusLoadAllPopulatesIndexAndContexts() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        // --- Seed a VALID Vault (PageType) at the nexus root, via save(to:). ---
        let vaultID = ULID.generate()
        let vaultName = "Notes"
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: vaultName, in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        let pageType = PageType(
            id: vaultID, title: vaultName, icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        try pageType.save(to: vaultFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))

        // --- Seed a VALID Page Collection inside the Vault. ---
        let collID = ULID.generate()
        let collName = "Daily"
        let collFolder = vaultFolder.appendingPathComponent(collName, isDirectory: true)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let collection = PageCollection(
            id: collID, typeID: vaultID, title: collName, folderURL: collFolder, modifiedAt: Date()
        )
        try collection.save(to: collFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))

        // --- Seed one VALID Page (.md) inside the Collection. ---
        let pageID = ULID.generate()
        let pageFrontmatter = PageFrontmatter(
            id: pageID, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date()
        )
        let pageURL = collFolder.appendingPathComponent("Monday.md")
        try PageFile(frontmatter: pageFrontmatter, body: "# Monday\n").save(to: pageURL)

        // --- Seed a VALID Space (tier 1). ---
        let spaceID = ULID.generate()
        let spaceName = "Personal"
        try Filesystem.createFolderWithMetadata(
            folderURL: NexusPaths.spaceFolderURL(forTitle: spaceName, in: nexus),
            metadataURL: NexusPaths.spaceMetadataURL(forTitle: spaceName, in: nexus),
            metadata: Space(id: spaceID, title: spaceName, color: nil, icon: nil, blocks: [], modifiedAt: Date())
        )

        // --- Seed a VALID Topic (tier 2). ---
        let topicID = ULID.generate()
        let topicName = "Productivity"
        let topicFolder = NexusPaths.topicFolderURL(forTitle: topicName, in: nexus)
        try FileManager.default.createDirectory(at: topicFolder, withIntermediateDirectories: true)
        try Topic(
            id: topicID, title: topicName, icon: nil, blocks: [], modifiedAt: Date()
        ).save(to: NexusPaths.topicMetadataURL(forTitle: topicName, in: nexus))

        // --- Construct all managers sharing ONE IndexUpdater over the fresh index. ---
        // Injection mirrors LoadAllIndexSyncTests (`manager.indexUpdater = IndexUpdater(index)`).
        let pageTypeManager = PageTypeManager(nexus: nexus)
        pageTypeManager.indexUpdater = IndexUpdater(index)
        let pageContentManager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        pageContentManager.indexUpdater = IndexUpdater(index)
        let spaceManager = SpaceManager(nexus: nexus)
        spaceManager.indexUpdater = IndexUpdater(index)
        let topicManager = TopicManager(nexus: nexus)
        topicManager.indexUpdater = IndexUpdater(index)

        // --- Run loadAll in the order the app does. ---
        await pageTypeManager.loadAll()
        let loadedVault = try #require(pageTypeManager.types.first { $0.id == vaultID })
        let loadedCollection = try #require(
            pageTypeManager.pageCollections(in: loadedVault).first { $0.id == collID }
        )
        await pageContentManager.loadAll(for: loadedVault)
        await pageContentManager.loadAll(for: loadedCollection)
        await spaceManager.loadAll()
        await topicManager.loadAll()

        // --- ASSERT: tier pickers see the Space + Topic. ---
        let tier1 = try await IndexQuery(index).entitiesByContextTarget(.contextTier(1))
        #expect(tier1.contains { $0.id == spaceID })

        let tier2 = try await IndexQuery(index).entitiesByContextTarget(.contextTier(2))
        #expect(tier2.contains { $0.id == topicID })

        // --- ASSERT: writing a real user property on the loaded Page does not
        // throw (no FK error 19). The seeded Page lives in the Collection; the
        // loaded PageMeta is fetched from the content manager's cache. ---
        let loadedPage = try #require(
            pageContentManager.pages(in: loadedCollection).first { $0.id == pageID }
        )
        // Use a tier value (a built-in, always-present relation property) so we
        // never depend on a user property existing on a brand-new Vault.
        try await pageContentManager.updatePageProperty(
            loadedPage,
            propertyID: ReservedPropertyID.tier1,
            newValue: .relation([spaceID]),
            vault: loadedVault,
            collection: loadedCollection
        )
        // updatePageProperty swallows an index FK failure onto pendingError
        // (it does not rethrow), so assert no pendingError accumulated either —
        // a surfaced FK error here is the symptom-equivalent of the toast.
        #expect(pageContentManager.pendingError == nil)
    }

    // MARK: - Test B — malformed Collection sidecar orphans child Pages

    /// Reproduces the FK error via decode-skip. A Page Collection whose
    /// `_pagecollection.json` OMITS the required `id` field
    /// (`PageCollection.init(from:)` → `c.decode(String.self, forKey: .id)`,
    /// non-optional) makes `PageCollection.load` throw, so PageTypeManager's
    /// `try?` skips it — it never lands in `page_collections`. A child Page
    /// upsert that still carries that Collection's id hits the
    /// `pages.page_collection_id` FK; Task 8 Bug B makes that NON-fatal — the page
    /// is retried without the missing collection and still indexed under its Vault.
    @Test func malformedCollectionSidecarOrphansChildPages() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        // --- VALID Vault. ---
        let vaultID = ULID.generate()
        let vaultName = "Notes"
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: vaultName, in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        let pageType = PageType(
            id: vaultID, title: vaultName, icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        try pageType.save(to: vaultFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))

        // --- MALFORMED Page Collection: the `_pagecollection.json` EXISTS (so
        // PageContentManager's Type-root walk excludes this folder — exclusion
        // keys on sidecar PRESENCE, not decodability) but OMITS the required
        // `id` field, so `PageCollection.load` throws and PageTypeManager's
        // `try?` skips it. We pin a known collection id so the orphaned child
        // page can reference it directly in the upsert below. ---
        let orphanCollID = ULID.generate()
        let collName = "Broken"
        let collFolder = vaultFolder.appendingPathComponent(collName, isDirectory: true)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let malformedCollSidecar = """
            {
              "type_id": "\(vaultID)",
              "modified_at": "2026-05-29T00:00:00Z",
              "schema_version": 1
            }
            """
        try FixtureFiles.writeJSON(
            malformedCollSidecar,
            to: collFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        )

        // --- One Page inside the malformed Collection. ---
        let pageID = ULID.generate()
        let pageFrontmatter = PageFrontmatter(
            id: pageID, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date()
        )
        let pageURL = collFolder.appendingPathComponent("Orphan.md")
        try PageFile(frontmatter: pageFrontmatter, body: "# Orphan\n").save(to: pageURL)

        // --- Wire + load. ---
        let pageTypeManager = PageTypeManager(nexus: nexus)
        pageTypeManager.indexUpdater = IndexUpdater(index)
        let pageContentManager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        pageContentManager.indexUpdater = IndexUpdater(index)

        await pageTypeManager.loadAll()
        let loadedVault = try #require(pageTypeManager.types.first { $0.id == vaultID })
        await pageContentManager.loadAll(for: loadedVault)
        await pageContentManager.loadAll(for: loadedVault)  // harmless idempotent re-run; no Collection to load

        // --- ASSERT: the malformed Collection is ABSENT from the in-memory
        // load AND from the `page_collections` index table. ---
        #expect(pageTypeManager.pageCollections(in: loadedVault).isEmpty)
        let collRowCount = try await index.dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM page_collections WHERE id = ?", arguments: [orphanCollID]
            ) ?? -1
        }
        #expect(collRowCount == 0)

        // --- ASSERT the reproduction: an upsert for the orphaned child Page
        // that references the (missing) Collection id THROWS SQLite error 19
        // (FOREIGN KEY constraint failed). Call IndexUpdater.upsertPage
        // directly — updatePageProperty swallows the index error onto
        // pendingError rather than rethrowing. The Vault itself IS in the index
        // (PageTypeManager.loadAll synced it), so the violation is isolated to
        // the page_collection_id FK. ---
        let orphanMeta = PageMeta(
            id: pageID, title: "Orphan", url: pageURL, frontmatter: pageFrontmatter
        )
        // Post-fix (Task 8 Bug B): upsertPage tolerates the orphaned-collection FK.
        // The Vault (page_type) IS indexed, so the page is retried WITHOUT the missing
        // collection and still lands under its type — no throw, no toast.
        try IndexUpdater(index).upsertPage(
            orphanMeta, pageTypeID: vaultID, pageCollectionID: orphanCollID
        )
        let pageRowCount = try await index.dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM pages WHERE id = ?", arguments: [pageID]
            ) ?? 0
        }
        #expect(pageRowCount == 1)
        let pageCollForPage = try await index.dbQueue.read { db in
            try String.fetchOne(
                db, sql: "SELECT page_collection_id FROM pages WHERE id = ?", arguments: [pageID]
            )
        }
        #expect(pageCollForPage == nil)  // missing collection nulled; page kept under its Vault
    }

    // MARK: - Test C — malformed Topic sidecar leaves tier-2 picker empty

    /// Reproduces the empty/under-populated tier picker via decode-skip. A
    /// Topic whose `_topic.json` OMITS the required `id` field
    /// (`Topic.init(from:)` → `c.decode(String.self, forKey: .id)`,
    /// non-optional) makes `Topic.load` throw, so TopicManager's `try?` skips
    /// it — it never lands in `contexts`, so the tier-2 picker reads empty.
    @Test func malformedTopicSidecarLeavesTierPickerEmpty() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        // --- MALFORMED Topic: `_topic.json` EXISTS (so the folder isn't a
        // cosmetic skip) but OMITS the required `id`, so `Topic.load` throws
        // and TopicManager's `try?` skips it. We can't pin the id (it's the
        // omitted field), so we assert the tier-2 picker is empty outright —
        // a successfully-loaded Topic would have produced exactly one row. ---
        let topicName = "Productivity"
        let topicFolder = NexusPaths.topicFolderURL(forTitle: topicName, in: nexus)
        try FileManager.default.createDirectory(at: topicFolder, withIntermediateDirectories: true)
        let malformedTopicSidecar = """
            {
              "tier": 2,
              "parents": [],
              "blocks": [],
              "modified_at": "2026-05-29T00:00:00Z"
            }
            """
        try FixtureFiles.writeJSON(
            malformedTopicSidecar,
            to: NexusPaths.topicMetadataURL(forTitle: topicName, in: nexus)
        )

        // --- Wire + load. ---
        let topicManager = TopicManager(nexus: nexus)
        topicManager.indexUpdater = IndexUpdater(index)
        await topicManager.loadAll()

        // --- ASSERT: the malformed Topic was skipped in-memory AND the tier-2
        // picker surfaces no Topics (reproducing the empty picker). ---
        #expect(topicManager.topics.isEmpty)
        let tier2 = try await IndexQuery(index).entitiesByContextTarget(.contextTier(2))
        #expect(tier2.isEmpty)
    }
}
