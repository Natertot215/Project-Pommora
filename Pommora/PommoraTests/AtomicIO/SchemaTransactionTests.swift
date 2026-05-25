import Foundation
import Testing
@testable import Pommora

@Suite("SchemaTransaction") struct SchemaTransactionTests {

    /// Builds a fresh per-test temp directory; cleaned up via `defer` by the caller.
    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pommora-schemaTxn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func commitWritesAllFilesAtomically() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.json")
        let b = dir.appendingPathComponent("b.json")

        let txn = SchemaTransaction()
        txn.stage(payload: Data("A".utf8), to: a)
        txn.stage(payload: Data("B".utf8), to: b)
        try txn.commit()

        #expect(try String(contentsOf: a, encoding: .utf8) == "A")
        #expect(try String(contentsOf: b, encoding: .utf8) == "B")
    }

    @Test func commitOverwritesExistingFiles() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.json")
        try Data("OLD".utf8).write(to: a)

        let txn = SchemaTransaction()
        txn.stage(payload: Data("NEW".utf8), to: a)
        try txn.commit()

        #expect(try String(contentsOf: a, encoding: .utf8) == "NEW")
        // No backup left behind on success.
        let siblings = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(siblings.allSatisfy { !$0.contains(".bak-") && !$0.contains(".txn-") })
    }

    @Test func rollbackOnStageFailureLeavesNoTempsAndPreservesExistingFiles() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let valid = dir.appendingPathComponent("valid.json")
        try Data("ORIGINAL".utf8).write(to: valid)
        // Force a stage failure by targeting a path whose parent doesn't exist.
        let invalid = dir.appendingPathComponent("does-not-exist").appendingPathComponent("x.json")

        let txn = SchemaTransaction()
        txn.stage(payload: Data("STAGED".utf8), to: valid)
        txn.stage(payload: Data("FAILS".utf8), to: invalid)

        #expect(throws: SchemaTransactionError.self) { try txn.commit() }

        // Pre-existing file untouched (still ORIGINAL, never written).
        #expect(try String(contentsOf: valid, encoding: .utf8) == "ORIGINAL")
        // No stale `.txn-*` files.
        let siblings = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(siblings.allSatisfy { !$0.contains(".txn-") })
    }

    @Test func idempotentCleansStaleTempsFromPriorCrash() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Simulate a previous crashed commit: leave a stale temp + backup behind.
        let staleTemp = dir.appendingPathComponent("a.json.txn-01HSTALE")
        let staleBak = dir.appendingPathComponent("a.json.bak-01HSTALE")
        try Data("STALE-TEMP".utf8).write(to: staleTemp)
        try Data("STALE-BAK".utf8).write(to: staleBak)

        let target = dir.appendingPathComponent("a.json")
        let txn = SchemaTransaction()
        txn.stage(payload: Data("FRESH".utf8), to: target)
        try txn.commit()

        // Stale files cleaned, target written correctly.
        #expect(!FileManager.default.fileExists(atPath: staleTemp.path))
        #expect(!FileManager.default.fileExists(atPath: staleBak.path))
        #expect(try String(contentsOf: target, encoding: .utf8) == "FRESH")
    }

    @Test func stageCodableValueRoundTrips() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("def.json")

        let def = PropertyDefinition(id: "prop_01H", name: "Status", type: .status)
        let txn = SchemaTransaction()
        try txn.stage(def, to: target)
        try txn.commit()

        let decoded = try AtomicJSON.decode(PropertyDefinition.self, from: target)
        #expect(decoded == def)
    }

    @Test func commitClearsPendingSoTransactionIsReusable() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.json")
        let b = dir.appendingPathComponent("b.json")

        let txn = SchemaTransaction()
        txn.stage(payload: Data("first".utf8), to: a)
        try txn.commit()
        #expect(try String(contentsOf: a, encoding: .utf8) == "first")

        // Reuse the same transaction object for a fresh write to a different file.
        txn.stage(payload: Data("second".utf8), to: b)
        try txn.commit()
        #expect(try String(contentsOf: b, encoding: .utf8) == "second")
        // First file unchanged by the second commit.
        #expect(try String(contentsOf: a, encoding: .utf8) == "first")
    }
}
