import Foundation
import GRDB
import Testing

@testable import Pommora

@Suite("ConnectionReconcileTests")
@MainActor
struct ConnectionReconcileTests {

    // MARK: - Helpers

    /// Insert a pages row (with its required page_collection parent) so reconcile's
    /// title lookup finds it. `pages.page_collection_id` is NOT NULL + FK to page_collections,
    /// so seed a shared parent row first (INSERT OR IGNORE — idempotent across calls).
    private func insertPage(id: String, title: String, index: PommoraIndex) throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = iso.string(from: Date())
        try index.dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO page_collections (id, title, modified_at) VALUES (?, ?, ?)",
                arguments: ["pc-test", "TestVault", now])
            try db.execute(
                sql: "INSERT INTO pages (id, page_collection_id, title, modified_at) VALUES (?, ?, ?, ?)",
                arguments: [id, "pc-test", title, now])
        }
    }

    private func readConnections(sourceID: String, index: PommoraIndex) throws -> [Row] {
        try index.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM connections WHERE source_id = ?", arguments: [sourceID])
        }
    }

    // MARK: - Tests

    /// Resolved + phantom + multiplicity: [[Target]] twice resolves; [[Ghost]] stays phantom.
    @Test func resolvedPhantomAndMultiplicity() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let targetID = ULID.generate()
        try insertPage(id: targetID, title: "Target", index: idx)

        try updater.reconcileConnections(
            sourceID: "S",
            sourceKind: "page",
            sourceTitle: "Source",
            body: "[[Target]] [[Ghost]] [[Target]]"
        )

        let rows = try readConnections(sourceID: "S", index: idx)
        #expect(rows.count == 2)

        let targetRow = rows.first { ($0["target_title"] as String?) == "target" }
        #expect(targetRow != nil)
        #expect(targetRow?["target_id"] as String? == targetID)
        #expect(targetRow?["resolved"] as Int? == 1)
        #expect(targetRow?["multiplicity"] as Int? == 2)

        let ghostRow = rows.first { ($0["target_title"] as String?) == "ghost" }
        #expect(ghostRow != nil)
        #expect((ghostRow?["target_id"] as String?) == nil)
        #expect(ghostRow?["resolved"] as Int? == 0)
    }

    /// Self-link guard: [[Self]] in a page titled "Self" produces zero rows.
    @Test func selfLinkIsSkipped() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        try updater.reconcileConnections(
            sourceID: "X",
            sourceKind: "page",
            sourceTitle: "Self",
            body: "[[Self]]"
        )

        let rows = try readConnections(sourceID: "X", index: idx)
        #expect(rows.isEmpty)
    }

    /// deactivateConnections flips a resolved row to NULL/0.
    @Test func deactivateFlipsResolvedToPhantom() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try Fixtures.index(at: nexus)
        let updater = IndexUpdater(idx)

        let targetID = ULID.generate()
        try insertPage(id: targetID, title: "Target", index: idx)

        try updater.reconcileConnections(
            sourceID: "S2",
            sourceKind: "page",
            sourceTitle: "Source",
            body: "[[Target]]"
        )

        // Verify resolved before deactivate.
        let before = try readConnections(sourceID: "S2", index: idx)
        #expect(before.count == 1)
        #expect(before[0]["resolved"] as Int? == 1)

        try updater.deactivateConnections(targetID: targetID)

        let after = try readConnections(sourceID: "S2", index: idx)
        #expect(after.count == 1)
        #expect((after[0]["target_id"] as String?) == nil)
        #expect(after[0]["resolved"] as Int? == 0)
    }
}
