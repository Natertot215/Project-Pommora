import Foundation
import Testing

@testable import Pommora

@Suite("SidecarRenameMigration")
struct SidecarRenameMigrationTests {

    // MARK: - Fixture

    /// A 4-level Pages tree in the OLD sidecar scheme, plus a Tasks folder that
    /// must be left untouched.
    private func makeLegacyNexus() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("sidecar-mig-\(UUID().uuidString)")
        let coll = root.appendingPathComponent("Assignments")
        let setA = coll.appendingPathComponent("Spring")
        let subB = setA.appendingPathComponent("Midterms")
        let subC = subB.appendingPathComponent("Week1")
        try fm.createDirectory(at: subC, withIntermediateDirectories: true)

        // top Collection — legacy `_pagetype.json`
        let collection = PageCollection(
            id: "coll1", title: "Assignments", icon: nil, properties: [], views: [], modifiedAt: Date())
        try collection.save(to: coll.appendingPathComponent("_pagetype.json"))

        // depth-1 Set — legacy `_pagecollection.json` + legacy `type_id`
        try writeLegacySet(
            id: "setA", parentID: "coll1", legacyKey: "type_id",
            to: setA.appendingPathComponent("_pagecollection.json"))
        // depth-2 — already `_pageset.json` but legacy `collection_id`
        try writeLegacySet(
            id: "subB", parentID: "setA", legacyKey: "collection_id",
            to: subB.appendingPathComponent("_pageset.json"))
        // depth-3 — `_pageset.json`, legacy `collection_id`
        try writeLegacySet(
            id: "subC", parentID: "subB", legacyKey: "collection_id",
            to: subC.appendingPathComponent("_pageset.json"))

        // a Tasks folder that must survive the migration untouched
        let tasks = root.appendingPathComponent("Tasks")
        try fm.createDirectory(at: tasks, withIntermediateDirectories: true)
        try "{}".write(
            to: tasks.appendingPathComponent("_taskconfig.json"), atomically: true, encoding: .utf8)

        return root
    }

    /// Encodes a canonical PageSet, then swaps `parent_id` for a legacy key —
    /// guaranteeing a valid date format while simulating pre-Phase-3 data.
    private func writeLegacySet(id: String, parentID: String, legacyKey: String, to url: URL) throws {
        let set = PageSet(
            id: id, parentID: parentID, title: "",
            folderURL: URL(fileURLWithPath: "/"), modifiedAt: Date())
        let data = try AtomicJSON.encode(set)
        let json = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\"parent_id\"", with: "\"\(legacyKey)\"")
        try json.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    // MARK: - Tests

    @Test("migrates a 4-level legacy tree to the unified scheme, bottom-up")
    func migratesFourLevels() throws {
        let root = try makeLegacyNexus()
        defer { try? FileManager.default.removeItem(at: root) }
        let coll = root.appendingPathComponent("Assignments")
        let setA = coll.appendingPathComponent("Spring")
        let subB = setA.appendingPathComponent("Midterms")
        let subC = subB.appendingPathComponent("Week1")

        let report = try SidecarRenameMigration.migrateIfNeeded(at: root)

        // top: _pagetype.json → _pagecollection.json
        #expect(exists(coll.appendingPathComponent("_pagecollection.json")))
        #expect(!exists(coll.appendingPathComponent("_pagetype.json")))
        // depth-1: _pagecollection.json → _pageset.json
        #expect(exists(setA.appendingPathComponent("_pageset.json")))
        #expect(!exists(setA.appendingPathComponent("_pagecollection.json")))
        // deeper stay _pageset.json
        #expect(exists(subB.appendingPathComponent("_pageset.json")))
        #expect(exists(subC.appendingPathComponent("_pageset.json")))

        // every Set sidecar canonicalized to parent_id, no legacy keys
        for s in [setA, subB, subC] {
            let json = try String(
                contentsOf: s.appendingPathComponent("_pageset.json"), encoding: .utf8)
            #expect(json.contains("\"parent_id\""))
            #expect(!json.contains("\"type_id\""))
            #expect(!json.contains("\"collection_id\""))
        }

        // parent links survive
        #expect(try PageSet.load(from: setA.appendingPathComponent("_pageset.json")).parentID == "coll1")
        #expect(try PageSet.load(from: subC.appendingPathComponent("_pageset.json")).parentID == "subB")

        // counts
        #expect(report.collectionsRenamed == 1)
        #expect(report.setsRenamed == 1)
        #expect(report.keysRewritten == 2)

        // Tasks folder untouched
        #expect(exists(root.appendingPathComponent("Tasks/_taskconfig.json")))

        // temp backup deleted on success
        let nexusDir = root.appendingPathComponent(".nexus")
        let leftovers =
            (try? FileManager.default.contentsOfDirectory(atPath: nexusDir.path))?
            .filter { $0.hasPrefix("migration-backup") } ?? []
        #expect(leftovers.isEmpty)
    }

    @Test("re-running on a migrated nexus is a no-op")
    func idempotent() throws {
        let root = try makeLegacyNexus()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try SidecarRenameMigration.migrateIfNeeded(at: root)
        #expect(try SidecarRenameMigration.migrateIfNeeded(at: root).noOp)
    }

    @Test("an already-unified nexus needs no migration")
    func cleanNexusNoOp() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("sidecar-clean-\(UUID().uuidString)")
        let coll = root.appendingPathComponent("Notes")
        try fm.createDirectory(at: coll, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let collection = PageCollection(
            id: "c", title: "Notes", icon: nil, properties: [], views: [], modifiedAt: Date())
        try collection.save(to: coll.appendingPathComponent("_pagecollection.json"))
        #expect(try SidecarRenameMigration.migrateIfNeeded(at: root).noOp)
    }
}
