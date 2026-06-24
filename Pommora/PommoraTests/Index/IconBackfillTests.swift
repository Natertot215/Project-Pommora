//
//  IconBackfillTests.swift
//  PommoraTests
//
//  Task 7 — v5 rebuild smoke-test. A full `IndexBuilder.populate` must backfill
//  entity icons into the index (so `ContextDisplayResolver.resolve` returns
//  icon + title) AND emit tier links into the `context_links` table. Complements
//  `IndexBuilderTests` (structure) + `TierRelationsEmitTests` (tier emit) with an
//  explicit icon-survives-rebuild assertion through `resolveEntities` — the
//  fixtures in those suites use `icon: nil`, so icon backfill was unasserted.
//
//  Struct name MATCHES the filename (quirk #18).
//

import Foundation
import GRDB
import Testing

@testable import Pommora

@MainActor
@Suite("IconBackfillTests")
struct IconBackfillTests {

    @Test func rebuildBackfillsIconsAndTierRelations() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // --- Seed a Area (tier 1) WITH an icon. ---
        let areaID = ULID.generate()
        try Filesystem.createFolderWithMetadata(
            folderURL: NexusPaths.areaFolderURL(forTitle: "Personal", in: nexus),
            metadataURL: NexusPaths.areaMetadataURL(forTitle: "Personal", in: nexus),
            metadata: Area(id: areaID, title: "Personal", icon: "person", blocks: [], modifiedAt: Date())
        )

        // --- Seed a PageCollection + a Page WITH an icon and tier1 = [Area]. ---
        let collectionManager = PageCollectionManager(nexus: nexus)
        await collectionManager.loadAll()
        try await collectionManager.createPageCollection(name: "Notes", icon: nil)
        let pt = collectionManager.types.first { $0.title == "Notes" }!
        _ = pt
        let typeFolder = NexusPaths.collectionFolderURL(forTitle: "Notes", in: nexus)

        let pageID = ULID.generate()
        let fm = PageFrontmatter(
            id: pageID, icon: "doc.text", tier1: [areaID], tier2: [], tier3: [],
            properties: [:], createdAt: Date(), modifiedAt: Date()
        )
        try AtomicYAMLMarkdown.write(
            frontmatter: fm, body: "", to: NexusPaths.pageFileURL(forTitle: "Monday", in: typeFolder))

        // --- Full rebuild from disk. ---
        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus)

        // --- Icons backfilled: resolveEntities returns icon + title for both. ---
        let resolved = try await IndexQuery(idx).resolveEntities(ids: [areaID, pageID])
        #expect(resolved[areaID]?.icon == "person")
        #expect(resolved[areaID]?.title == "Personal")
        #expect(resolved[pageID]?.icon == "doc.text")

        // --- Tier link emitted into `context_links` (page --tier1--> area), via the
        // tested reverse-lookup query rather than raw SQL. ---
        let incoming = try await IndexQuery(idx).incomingContextLinks(targetID: areaID)
        #expect(incoming.contains { $0.id == pageID })
    }
}
