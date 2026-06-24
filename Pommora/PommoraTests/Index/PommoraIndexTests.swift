import Foundation
import GRDB
import Testing

@testable import Pommora

@Suite("PommoraIndex")
struct PommoraIndexTests {

    private func tempNexusRoot() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PommoraIndexTest-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Test 1: fresh open creates DB + meta but DEFERS the version stamp

    /// A fresh open creates the DB + meta table and signals needsRebuild, but
    /// must NOT stamp `schema_version` yet — that's deferred to
    /// `markSchemaVersionCurrent()` after a successful populate, so a
    /// rolled-back rebuild can't lock an empty index in place. After stamping,
    /// the version reads back as current.
    @Test func freshOpenDefersSchemaVersionStampUntilMarked() throws {
        let root = tempNexusRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let (index, needsRebuild) = try PommoraIndex.open(at: root)
        #expect(needsRebuild == true)
        #expect(FileManager.default.fileExists(atPath: index.dbURL.path))

        // Version is NOT stamped on fresh open (the bug was stamping it here).
        let before = try index.dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'schema_version'")
        }
        #expect(before == nil)

        // Stamping (what NexusManager does after populate) writes the current version.
        try index.markSchemaVersionCurrent()
        let after = try index.dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'schema_version'")
        }
        #expect(after == String(PommoraIndex.currentSchemaVersion))
    }

    // MARK: - Test 2: reopeningSameDBReturnsNotNeedsRebuild

    @Test func reopeningSameDBReturnsNotNeedsRebuild() throws {
        let root = tempNexusRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // Stamp after the first open (mirrors NexusManager stamping post-populate);
        // only then does a re-open see a matching version and skip the rebuild.
        let (idx, _) = try PommoraIndex.open(at: root)
        try idx.markSchemaVersionCurrent()
        let (_, needsRebuild) = try PommoraIndex.open(at: root)
        #expect(needsRebuild == false)
    }

    // MARK: - Test 3: schemaVersionMismatchTriggersRebuild

    @Test func schemaVersionMismatchTriggersRebuild() throws {
        let root = tempNexusRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // First open + stamp seeds the current schema version, then we force a
        // mismatch by writing a bogus version.
        let (idx1, _) = try PommoraIndex.open(at: root)
        try idx1.markSchemaVersionCurrent()
        try idx1.dbQueue.write { db in
            try db.execute(sql: "UPDATE meta SET value = '99' WHERE key = 'schema_version'")
        }
        // Force connection release before reopen.
        // (GRDB DatabaseQueue auto-releases on dealloc — test scope ensures this.)
        let (_, needsRebuild) = try PommoraIndex.open(at: root)
        #expect(needsRebuild == true)
    }

    // MARK: - Test 4: corruptedFileTriggersRebuild

    @Test func allTablesExistAfterOpen() throws {
        let root = tempNexusRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (index, _) = try PommoraIndex.open(at: root)
        let expected: [String] = [
            "meta", "page_collections",
            "pages", "agenda_tasks", "agenda_events", "contexts",
            "context_links", "property_definitions",
        ]
        let actual = try index.dbQueue.read { db -> Set<String> in
            let names = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            return Set(names)
        }
        for table in expected {
            #expect(actual.contains(table), "Missing table: \(table)")
        }

        // PagesV2 P7 (schema v11): the item tables must NOT exist in a fresh index.
        for dropped in ["items", "item_types", "item_collections"] {
            #expect(!actual.contains(dropped), "Dropped item table resurfaced: \(dropped)")
        }
    }

    @Test func corruptedFileTriggersRebuild() throws {
        let root = tempNexusRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let nexusDir = root.appendingPathComponent(".nexus")
        try FileManager.default.createDirectory(at: nexusDir, withIntermediateDirectories: true)
        try "not a sqlite file at all".write(
            to: nexusDir.appendingPathComponent("index.db"), atomically: true, encoding: .utf8)

        let (_, needsRebuild) = try PommoraIndex.open(at: root)
        #expect(needsRebuild == true)
    }
}
