import Foundation
import GRDB
import Testing

@testable import Pommora

// MARK: - Suite

/// Tier values (`tier1`/`tier2`/`tier3`) must be mirrored into the `relations`
/// table — not only the legacy `tier_links` table — so the reverse-view query
/// `IndexQuery.incomingRelations(targetID:)` (which reads `relations`) surfaces
/// tier-based links to a Context. Covers both index paths:
/// `IndexUpdater` (incremental upsert) and `IndexBuilder` (full rebuild).
///
/// Struct name MATCHES the filename (`-only-testing:PommoraTests/TierRelationsEmitTests`
/// — Swift Testing filters by suite/type name, not source filename).
@Suite("TierRelationsEmitTests")
@MainActor
struct TierRelationsEmitTests {

    // MARK: - Helpers (mirror IndexUpdaterTests)

    private func makeIndex(at nexus: Nexus) throws -> PommoraIndex {
        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        return idx
    }

    private func tierRelationCount(targetID: String, propertyID: String, db index: PommoraIndex) throws -> Int {
        try index.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM relations WHERE target_id = ? AND property_id = ?",
                arguments: [targetID, propertyID]
            ) ?? -1
        }
    }

    private func makePageType(title: String = "Notes") -> PageType {
        PageType(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
    }

    private func makeItemType(title: String = "Tasks") -> ItemType {
        ItemType(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
    }

    // MARK: - IndexUpdater (incremental) — Page tier1

    @Test func upsertPageEmitsTier1RelationRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = makePageType()
        try updater.upsertPageType(pt)

        let contextID = ULID.generate()
        let pageID = ULID.generate()
        let url = URL(fileURLWithPath: "/tmp/\(pageID).md")
        let frontmatter = PageFrontmatter(
            id: pageID, icon: nil,
            tier1: [contextID], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date()
        )
        let meta = PageMeta(id: pageID, title: "Doc", url: url, frontmatter: frontmatter)
        try updater.upsertPage(meta, pageTypeID: pt.id, pageCollectionID: nil)

        // The relations row exists and carries the reserved tier property id + space target kind.
        let count = try tierRelationCount(targetID: contextID, propertyID: ReservedPropertyID.tier1, db: idx)
        #expect(count == 1)

        // incomingRelations (reverse view over `relations`) finds the page.
        let incoming = try await IndexQuery(idx).incomingRelations(targetID: contextID)
        #expect(incoming.contains { $0.id == pageID })

        // target_kind derives from the shared RelationTargetKind mapper (tier 1 → "space").
        let targetKind = try await idx.dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT target_kind FROM relations WHERE target_id = ? AND property_id = ?",
                arguments: [contextID, ReservedPropertyID.tier1]
            )
        }
        #expect(targetKind == RelationTargetKind.string(from: .contextTier(1)))
    }

    // MARK: - IndexUpdater (incremental) — Item across tiers 2 & 3

    @Test func upsertItemEmitsTier2AndTier3RelationRows() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let it = makeItemType()
        try updater.upsertItemType(it)

        let topicID = ULID.generate()
        let projectID = ULID.generate()
        let now = Date()
        let item = Item(
            id: ULID.generate(), title: "Widget", icon: nil, description: "",
            tier1: [], tier2: [topicID], tier3: [projectID],
            properties: [:],
            createdAt: now, modifiedAt: now
        )
        try updater.upsertItem(item, itemTypeID: it.id, itemCollectionID: nil)

        #expect(try tierRelationCount(targetID: topicID, propertyID: ReservedPropertyID.tier2, db: idx) == 1)
        #expect(try tierRelationCount(targetID: projectID, propertyID: ReservedPropertyID.tier3, db: idx) == 1)

        let incomingTopic = try await IndexQuery(idx).incomingRelations(targetID: topicID)
        #expect(incomingTopic.contains { $0.id == item.id })
        let incomingProject = try await IndexQuery(idx).incomingRelations(targetID: projectID)
        #expect(incomingProject.contains { $0.id == item.id })
    }

    // MARK: - IndexUpdater (incremental) — re-upsert does not duplicate or wipe

    @Test func reUpsertPageReplacesTierRelationsWithoutDuplication() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let pt = makePageType()
        try updater.upsertPageType(pt)

        let contextID = ULID.generate()
        let pageID = ULID.generate()
        let url = URL(fileURLWithPath: "/tmp/\(pageID).md")
        let frontmatter = PageFrontmatter(
            id: pageID, icon: nil,
            tier1: [contextID], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date()
        )
        let meta = PageMeta(id: pageID, title: "Doc", url: url, frontmatter: frontmatter)
        try updater.upsertPage(meta, pageTypeID: pt.id, pageCollectionID: nil)
        // Re-index the same page (e.g. an unrelated edit) — DELETE-then-reinsert must not duplicate.
        try updater.upsertPage(meta, pageTypeID: pt.id, pageCollectionID: nil)

        #expect(try tierRelationCount(targetID: contextID, propertyID: ReservedPropertyID.tier1, db: idx) == 1)
    }

    // MARK: - IndexBuilder (full rebuild) — Page tier1 survives populate

    @Test func fullRebuildEmitsTierRelationRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)

        // Lay down a real Page Type folder + one page with a tier1 frontmatter value,
        // then run a full IndexBuilder.populate against the on-disk nexus.
        let contextID = ULID.generate()
        let typeFolder = nexus.rootURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)

        let pageType = PageType(
            id: ULID.generate(), title: "Notes", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        try pageType.save(to: typeFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))

        let pageID = ULID.generate()
        let frontmatter = PageFrontmatter(
            id: pageID, icon: nil,
            tier1: [contextID], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date()
        )
        let pageFile = PageFile(frontmatter: frontmatter, body: "# Doc\n")
        try pageFile.save(to: typeFolder.appendingPathComponent("Doc.md"))

        try await IndexBuilder.populate(index: idx, from: nexus)

        #expect(try tierRelationCount(targetID: contextID, propertyID: ReservedPropertyID.tier1, db: idx) == 1)

        let incoming = try await IndexQuery(idx).incomingRelations(targetID: contextID)
        #expect(incoming.contains { $0.id == pageID })
    }
}
