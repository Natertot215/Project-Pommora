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

    // MARK: - Test 1: freshOpenCreatesDBAndMetaWithSchemaVersion1

    @Test func freshOpenCreatesDBAndMetaWithCurrentSchemaVersion() throws {
        let root = tempNexusRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let (index, needsRebuild) = try PommoraIndex.open(at: root)
        #expect(needsRebuild == true)
        #expect(FileManager.default.fileExists(atPath: index.dbURL.path))

        try index.dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'schema_version'")
            #expect(row?["value"] as String? == String(PommoraIndex.currentSchemaVersion))
        }
    }

    // MARK: - Test 2: reopeningSameDBReturnsNotNeedsRebuild

    @Test func reopeningSameDBReturnsNotNeedsRebuild() throws {
        let root = tempNexusRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try PommoraIndex.open(at: root)
        let (_, needsRebuild) = try PommoraIndex.open(at: root)
        #expect(needsRebuild == false)
    }

    // MARK: - Test 3: schemaVersionMismatchTriggersRebuild

    @Test func schemaVersionMismatchTriggersRebuild() throws {
        let root = tempNexusRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // First open seeds the current schema version.
        let (idx1, _) = try PommoraIndex.open(at: root)
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
            "meta", "page_types", "item_types", "page_collections", "item_collections",
            "pages", "items", "agenda_tasks", "agenda_events", "contexts",
            "relations", "property_definitions"
        ]
        let actual = try index.dbQueue.read { db -> Set<String> in
            let names = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            return Set(names)
        }
        for table in expected {
            #expect(actual.contains(table), "Missing table: \(table)")
        }
    }

    @Test func corruptedFileTriggersRebuild() throws {
        let root = tempNexusRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let nexusDir = root.appendingPathComponent(".nexus")
        try FileManager.default.createDirectory(at: nexusDir, withIntermediateDirectories: true)
        try "not a sqlite file at all".write(to: nexusDir.appendingPathComponent("index.db"), atomically: true, encoding: .utf8)

        let (_, needsRebuild) = try PommoraIndex.open(at: root)
        #expect(needsRebuild == true)
    }
}
