//
//  RebuildResilienceTests.swift
//  PommoraTests
//
//  FAILING REPRODUCTION (systematic debugging — reproduce before fixing) for
//  the rebuild-resilience bug in `IndexBuilder.populate`
//  (`Index/IndexBuilder.swift:139-155`):
//
//    `populate` runs `clearAllTables` + every insert inside ONE
//    `dbQueue.write` transaction, with FKs enforced and PLAIN `INSERT`
//    (not `INSERT OR REPLACE`). If ANY single row throws — e.g. a
//    duplicate-PRIMARY-KEY page from a legacy/adoption collision, or an FK
//    violation — GRDB rolls back the WHOLE transaction. The index is then
//    left EMPTY, including the valid Contexts the rebuild was supposed to
//    populate. This is why the running app shows an empty tier picker and
//    page upserts then FK-fail.
//
//  DESIRED behavior (which a resilient-rebuild fix will satisfy): one bad row
//  is skipped, and every VALID entity — notably the Contexts that back the
//  tier picker — survives the rebuild.
//
//  This test asserts that DESIRED outcome, so it FAILS on the current
//  all-or-nothing transaction (contexts come back EMPTY) = reproduces the
//  bug, and will PASS once the rebuild skips the bad page instead of rolling
//  the whole transaction back.
//
//  Setup mirrors `PommoraTests/Index/IndexPopulationReproTests.swift` and
//  `PommoraTests/Nexus/LoadAllIndexSyncTests.swift` verbatim (TempNexus on
//  disk, `PommoraIndex.open(at:)`, `PageFile(...).save(to:)` /
//  `Space(...).save(...)` / `Topic(...).save(...)` seeding via `NexusPaths`
//  helpers, `IndexQuery(index).entitiesByContextTarget(.contextTier(N))`). The one
//  new ingredient vs. IndexPopulationRepro is that this drives the real
//  `IndexBuilder.populate(index:from:)` directly (the bug lives in `populate`,
//  not in the manager `loadAll` sync path).
//
//  How the throwing row is forced: TWO Page `.md` files are written into one
//  Vault whose frontmatter carries the SAME `id`. `PageFrontmatter.id` decodes
//  straight from the file (`decode(String.self, forKey: .id)`), so both files
//  produce `PageSnapshot`s sharing that id. `pages.id` is `TEXT PRIMARY KEY`
//  (`IndexSchema.pagesDDL`) and `IndexBuilder.insertPage` emits a plain
//  `INSERT INTO pages`, so the second page throws a PRIMARY KEY violation
//  inside the single `populate` transaction.
//
//  Struct name MATCHES the filename (quirk #18 — Swift Testing filters by
//  suite/type name, not source filename).
//
//  Test only — does NOT fix or touch production code.
//

import Foundation
import GRDB
import Testing

@testable import Pommora

@MainActor
@Suite("RebuildResilienceTests")
struct RebuildResilienceTests {

    /// One bad (duplicate-PRIMARY-KEY) Page during `IndexBuilder.populate`
    /// must NOT wipe the valid Contexts. Asserts the resilient-rebuild
    /// outcome, so it FAILS on the current all-or-nothing transaction
    /// (contexts roll back to empty) and PASSES once the bad row is skipped.
    @Test func oneBadPageMustNotWipeValidContexts() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        // --- Seed a VALID Space (tier 1). ---
        let spaceID = ULID.generate()
        let spaceName = "Personal"
        let spacesDir = NexusPaths.spacesDir(in: nexus)
        try FileManager.default.createDirectory(at: spacesDir, withIntermediateDirectories: true)
        try Space(
            id: spaceID, title: spaceName, color: nil, icon: nil, blocks: [], modifiedAt: Date()
        ).save(to: NexusPaths.spaceFileURL(forTitle: spaceName, in: nexus))

        // --- Seed a VALID Topic (tier 2). ---
        let topicID = ULID.generate()
        let topicName = "Productivity"
        let topicFolder = NexusPaths.topicFolderURL(forTitle: topicName, in: nexus)
        try FileManager.default.createDirectory(at: topicFolder, withIntermediateDirectories: true)
        try Topic(
            id: topicID, title: topicName, icon: nil, blocks: [], modifiedAt: Date()
        ).save(to: NexusPaths.topicMetadataURL(forTitle: topicName, in: nexus))

        // --- Seed a VALID Vault (PageType) at the nexus root. ---
        let vaultID = ULID.generate()
        let vaultName = "Notes"
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: vaultName, in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        let pageType = PageType(
            id: vaultID, title: vaultName, icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        try pageType.save(to: vaultFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))

        // --- Seed TWO Page `.md` files in the Vault whose frontmatter carries
        // the SAME `id` (a realistic legacy/adoption primary-key collision).
        // `PageFrontmatter.id` decodes straight from each file, so both produce
        // PageSnapshots with the same id; `pages.id` is TEXT PRIMARY KEY, so
        // `IndexBuilder.insertPage`'s plain `INSERT INTO pages` throws a PRIMARY
        // KEY violation on the second page — the one bad row inside the single
        // `populate` transaction. ---
        let duplicateID = ULID.generate()
        let frontmatterA = PageFrontmatter(
            id: duplicateID, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date()
        )
        try PageFile(frontmatter: frontmatterA, body: "# First\n")
            .save(to: vaultFolder.appendingPathComponent("First.md"))
        let frontmatterB = PageFrontmatter(
            id: duplicateID, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date()
        )
        try PageFile(frontmatter: frontmatterB, body: "# Second\n")
            .save(to: vaultFolder.appendingPathComponent("Second.md"))

        // --- Run the real rebuild. With the resilient-rebuild fix, `populate`
        // skips the duplicate-PK page instead of rolling the whole transaction
        // back, so it does NOT throw. `try` (not `try?`) surfaces any unexpected
        // failure as a test failure rather than silently swallowing it. ---
        try await IndexBuilder.populate(index: index, from: nexus)

        // --- ASSERT the DESIRED outcome: the valid Contexts SURVIVED the
        // rebuild despite the one bad Page. On current all-or-nothing code the
        // rollback leaves `contexts` EMPTY, so both assertions FAIL =
        // reproduction. Once the rebuild skips the dup page, the contexts land
        // and both assertions PASS. ---
        let tier1 = try await IndexQuery(index).entitiesByContextTarget(.contextTier(1))
        #expect(tier1.contains { $0.id == spaceID })

        let tier2 = try await IndexQuery(index).entitiesByContextTarget(.contextTier(2))
        #expect(tier2.contains { $0.id == topicID })
    }
}
