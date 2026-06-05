import Foundation
import GRDB
import Testing

@testable import Pommora

// MARK: - Suite

/// Tier values (`tier1`/`tier2`/`tier3`) must be emitted into the `context_links`
/// table so the reverse-view query `IndexQuery.incomingRelations(targetID:)`
/// (which reads `context_links`) surfaces tier-based links to a Context. Covers both
/// index paths: `IndexUpdater` (incremental upsert) and `IndexBuilder` (full rebuild).
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
                sql: "SELECT COUNT(*) FROM context_links WHERE target_id = ? AND property_id = ?",
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

    private func makeAgendaTask(
        title: String = "Buy milk",
        tier1: [String] = [],
        tier2: [String] = [],
        tier3: [String] = []
    ) -> AgendaTask {
        let now = Date()
        return AgendaTask(
            id: ULID.generate(), title: title, icon: nil,
            description: "",
            dueAt: nil, dueFloating: false, dueAllDay: false,
            startAt: nil, completed: false, completedAt: nil,
            priority: 0, recurrence: nil, alarmOffsets: [],
            calendarID: nil, eventkitUUID: nil,
            tier1: tier1, tier2: tier2, tier3: tier3,
            createdAt: now, modifiedAt: now,
            properties: [:]
        )
    }

    private func relationCount(sourceID: String, db index: PommoraIndex) throws -> Int {
        try index.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM context_links WHERE source_id = ?",
                arguments: [sourceID]
            ) ?? -1
        }
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
                sql: "SELECT target_kind FROM context_links WHERE target_id = ? AND property_id = ?",
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

    // MARK: - IndexUpdater (incremental) — AgendaTask tier1

    @Test func upsertAgendaTaskEmitsTier1RelationRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let contextID = ULID.generate()
        let task = makeAgendaTask(tier1: [contextID])
        try updater.upsertAgendaTask(task)

        // The relations row exists and carries the reserved tier property id.
        let count = try tierRelationCount(targetID: contextID, propertyID: ReservedPropertyID.tier1, db: idx)
        #expect(count == 1)

        // incomingRelations (reverse view over `relations`) finds the task.
        let incoming = try await IndexQuery(idx).incomingRelations(targetID: contextID)
        #expect(incoming.contains { $0.id == task.id })

        // target_kind derives from the shared RelationTargetKind mapper (tier 1 → "space").
        let targetKind = try await idx.dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT target_kind FROM context_links WHERE target_id = ? AND property_id = ?",
                arguments: [contextID, ReservedPropertyID.tier1]
            )
        }
        #expect(targetKind == RelationTargetKind.string(from: .contextTier(1)))
    }

    // MARK: - IndexUpdater (incremental) — deleteAgendaTask cleans relations

    @Test func deleteAgendaTaskClearsRelations() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let contextID = ULID.generate()
        let task = makeAgendaTask(tier1: [contextID])
        try updater.upsertAgendaTask(task)

        // Sanity: the relations row was written by the upsert.
        #expect(try relationCount(sourceID: task.id, db: idx) == 1)

        try updater.deleteAgendaTask(id: task.id)

        // The relations table is cleaned for the deleted task.
        #expect(try relationCount(sourceID: task.id, db: idx) == 0)
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

    // MARK: - Guard — user-relation property values must NOT emit relations rows

    /// A `.relation([id])` property value on a page must NOT produce any row in
    /// the `relations` table; only tier values should. This encodes the post-Task-6
    /// contract: user-relation indexing is removed; the tier paths are the sole
    /// `relations` emitters.
    @Test func userRelationPropertyValueEmitsNoRelationsRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        // Register a page type with one relation property definition.
        let relPropID = ULID.generate()
        let relDef = PropertyDefinition(id: relPropID, name: "Linked", type: .relation)
        let pt = PageType(
            id: ULID.generate(), title: "Notes", icon: nil,
            properties: [relDef], views: [], modifiedAt: Date()
        )
        try updater.upsertPageType(pt)

        // Create a page whose `properties` map carries a `.relation` value.
        let targetID = ULID.generate()
        let pageID = ULID.generate()
        let url = URL(fileURLWithPath: "/tmp/\(pageID).md")
        let frontmatter = PageFrontmatter(
            id: pageID, icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [relPropID: .relation([targetID])],
            createdAt: Date()
        )
        let meta = PageMeta(id: pageID, title: "Doc", url: url, frontmatter: frontmatter)
        try updater.upsertPage(meta, pageTypeID: pt.id, pageCollectionID: nil)

        // The user-relation value must NOT appear in relations.
        let userRelCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM context_links WHERE source_id = ? AND property_id = ?",
                arguments: [pageID, relPropID]
            ) ?? -1
        }
        #expect(userRelCount == 0, "user-relation property values must not emit relations rows")

        // Total relations for this page must also be 0 (no tier values were set).
        #expect(try relationCount(sourceID: pageID, db: idx) == 0)
    }

    /// Companion to `userRelationPropertyValueEmitsNoRelationsRow`: when a page
    /// carries BOTH a `.relation` property value AND a tier value, only the tier
    /// row lands in `relations`.
    @Test func userRelationWithTierEmitsOnlyTierRow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)

        let relPropID = ULID.generate()
        let relDef = PropertyDefinition(id: relPropID, name: "Linked", type: .relation)
        let pt = PageType(
            id: ULID.generate(), title: "Notes", icon: nil,
            properties: [relDef], views: [], modifiedAt: Date()
        )
        try updater.upsertPageType(pt)

        let userTargetID = ULID.generate()
        let contextID = ULID.generate()
        let pageID = ULID.generate()
        let url = URL(fileURLWithPath: "/tmp/\(pageID).md")
        let frontmatter = PageFrontmatter(
            id: pageID, icon: nil,
            tier1: [contextID], tier2: [], tier3: [],
            properties: [relPropID: .relation([userTargetID])],
            createdAt: Date()
        )
        let meta = PageMeta(id: pageID, title: "Doc", url: url, frontmatter: frontmatter)
        try updater.upsertPage(meta, pageTypeID: pt.id, pageCollectionID: nil)

        // Exactly one row — the tier1 row — must exist.
        #expect(try relationCount(sourceID: pageID, db: idx) == 1)

        // That row must be the tier row, not the user-relation row.
        let tierCount = try tierRelationCount(targetID: contextID, propertyID: ReservedPropertyID.tier1, db: idx)
        #expect(tierCount == 1)

        // The user-relation target must not appear at all.
        let userRelCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM context_links WHERE target_id = ?",
                arguments: [userTargetID]
            ) ?? -1
        }
        #expect(userRelCount == 0, "user-relation target must not appear in context_links after Task 6")
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
