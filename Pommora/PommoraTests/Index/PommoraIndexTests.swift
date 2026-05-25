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

    @Test func freshOpenCreatesDBAndMetaWithSchemaVersion1() throws {
        let root = tempNexusRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let (index, needsRebuild) = try PommoraIndex.open(at: root)
        #expect(needsRebuild == true)
        #expect(FileManager.default.fileExists(atPath: index.dbURL.path))

        try index.dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'schema_version'")
            #expect(row?["value"] as String? == "1")
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

        // First open seeds version 1.
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
