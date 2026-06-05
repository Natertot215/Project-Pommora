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

        // --- Seed a Space (tier 1) WITH an icon. ---
        let spaceID = ULID.generate()
        let spacesDir = NexusPaths.spacesDir(in: nexus)
        try FileManager.default.createDirectory(at: spacesDir, withIntermediateDirectories: true)
        try Space(
            id: spaceID, title: "Personal", color: nil, icon: "person", blocks: [], modifiedAt: Date()
        ).save(to: NexusPaths.spaceFileURL(forTitle: "Personal", in: nexus))

        // --- Seed a PageType + a Page WITH an icon and tier1 = [Space]. ---
        let pageTypeManager = PageTypeManager(nexus: nexus)
        await pageTypeManager.loadAll()
        try await pageTypeManager.createPageType(name: "Notes", icon: nil)
        let pt = pageTypeManager.types.first { $0.title == "Notes" }!
        _ = pt
        let typeFolder = NexusPaths.vaultFolderURL(forTitle: "Notes", in: nexus)

        let pageID = ULID.generate()
        let fm = PageFrontmatter(
            id: pageID, icon: "doc.text", tier1: [spaceID], tier2: [], tier3: [],
            properties: [:], createdAt: Date(), modifiedAt: Date()
        )
        try AtomicYAMLMarkdown.write(
            frontmatter: fm, body: "", to: NexusPaths.pageFileURL(forTitle: "Monday", in: typeFolder))

        // --- Full rebuild from disk. ---
        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus)

        // --- Icons backfilled: resolveEntities returns icon + title for both. ---
        let resolved = try await IndexQuery(idx).resolveEntities(ids: [spaceID, pageID])
        #expect(resolved[spaceID]?.icon == "person")
        #expect(resolved[spaceID]?.title == "Personal")
        #expect(resolved[pageID]?.icon == "doc.text")

        // --- Tier link emitted into `context_links` (page --tier1--> space), via the
        // tested reverse-lookup query rather than raw SQL. ---
        let incoming = try await IndexQuery(idx).incomingContextLinks(targetID: spaceID)
        #expect(incoming.contains { $0.id == pageID })
    }
}
