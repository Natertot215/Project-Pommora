import Foundation
import GRDB
import Testing

@testable import Pommora

@Suite("IndexQuery")
@MainActor
struct IndexQueryTests {

    private func setupIndex() async throws -> (URL, PommoraIndex) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IndexQueryTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (idx, _) = try PommoraIndex.open(at: dir)
        return (dir, idx)
    }

    // MARK: - Filter: equals

    @Test func filterEqualsOnPropertyJSON() async throws {
        let (dir, idx) = try await setupIndex()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await idx.dbQueue.write { db in
            try db.execute(sql: "INSERT INTO page_types(id, title, modified_at) VALUES ('PT1', 'Notes', '2026-05-24T00:00:00Z')")
            try db.execute(sql: """
                INSERT INTO pages(id, page_type_id, title, properties, modified_at) VALUES
                ('P1', 'PT1', 'One',   '{"prop_A":"active"}',   '2026-05-24T00:00:00Z'),
                ('P2', 'PT1', 'Two',   '{"prop_A":"archived"}', '2026-05-24T00:00:00Z'),
                ('P3', 'PT1', 'Three', '{"prop_A":"active"}',   '2026-05-24T00:00:00Z')
            """)
        }

        let results = try await IndexQuery(idx).filter([
            .equals(propertyID: "prop_A", value: .select("active"))
        ], in: .pageType("PT1"))

        #expect(results.count == 2)
        let ids = Set(results.map(\.id))
        #expect(ids == ["P1", "P3"])
    }

    // MARK: - Filter: inSet

    @Test func filterInSetMatchesAny() async throws {
        let (dir, idx) = try await setupIndex()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await idx.dbQueue.write { db in
            try db.execute(sql: "INSERT INTO item_types(id, title, modified_at) VALUES ('IT1', 'Tasks', '2026-05-24T00:00:00Z')")
            try db.execute(sql: """
                INSERT INTO items(id, item_type_id, title, properties, modified_at) VALUES
                ('I1', 'IT1', 'Alpha',   '{"status":"open"}',        '2026-05-24T00:00:00Z'),
                ('I2', 'IT1', 'Beta',    '{"status":"closed"}',      '2026-05-24T00:00:00Z'),
                ('I3', 'IT1', 'Gamma',   '{"status":"in_progress"}', '2026-05-24T00:00:00Z'),
                ('I4', 'IT1', 'Delta',   '{"status":"archived"}',    '2026-05-24T00:00:00Z')
            """)
        }

        let results = try await IndexQuery(idx).filter([
            .inSet(propertyID: "status", values: [.select("open"), .select("in_progress")])
        ], in: .itemType("IT1"))

        #expect(results.count == 2)
        let ids = Set(results.map(\.id))
        #expect(ids == ["I1", "I3"])
    }

    // MARK: - Filter: notInSet

    @Test func filterNotInSetExcludesValues() async throws {
        let (dir, idx) = try await setupIndex()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await idx.dbQueue.write { db in
            try db.execute(sql: "INSERT INTO page_types(id, title, modified_at) VALUES ('PT2', 'Docs', '2026-05-24T00:00:00Z')")
            try db.execute(sql: """
                INSERT INTO pages(id, page_type_id, title, properties, modified_at) VALUES
                ('P10', 'PT2', 'A', '{"priority":"high"}',   '2026-05-24T00:00:00Z'),
                ('P11', 'PT2', 'B', '{"priority":"medium"}', '2026-05-24T00:00:00Z'),
                ('P12', 'PT2', 'C', '{"priority":"low"}',    '2026-05-24T00:00:00Z')
            """)
        }

        let results = try await IndexQuery(idx).filter([
            .notInSet(propertyID: "priority", values: [.select("high")])
        ], in: .pageType("PT2"))

        #expect(results.count == 2)
        let ids = Set(results.map(\.id))
        #expect(ids == ["P11", "P12"])
    }

    // MARK: - Filter: AND composition

    @Test func filterAndComposesAcrossProperties() async throws {
        let (dir, idx) = try await setupIndex()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await idx.dbQueue.write { db in
            try db.execute(sql: "INSERT INTO page_types(id, title, modified_at) VALUES ('PT3', 'Projects', '2026-05-24T00:00:00Z')")
            try db.execute(sql: """
                INSERT INTO pages(id, page_type_id, title, properties, modified_at) VALUES
                ('P20', 'PT3', 'AA', '{"status":"active","priority":"high"}',   '2026-05-24T00:00:00Z'),
                ('P21', 'PT3', 'AB', '{"status":"active","priority":"low"}',    '2026-05-24T00:00:00Z'),
                ('P22', 'PT3', 'BA', '{"status":"archived","priority":"high"}', '2026-05-24T00:00:00Z')
            """)
        }

        let results = try await IndexQuery(idx).filter([
            .and([
                .equals(propertyID: "status", value: .select("active")),
                .equals(propertyID: "priority", value: .select("high"))
            ])
        ], in: .pageType("PT3"))

        #expect(results.count == 1)
        #expect(results[0].id == "P20")
    }

    // MARK: - Filter: OR composition

    @Test func filterOrComposesAlternatives() async throws {
        let (dir, idx) = try await setupIndex()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await idx.dbQueue.write { db in
            try db.execute(sql: "INSERT INTO page_types(id, title, modified_at) VALUES ('PT4', 'Misc', '2026-05-24T00:00:00Z')")
            try db.execute(sql: """
                INSERT INTO pages(id, page_type_id, title, properties, modified_at) VALUES
                ('P30', 'PT4', 'X', '{"tag":"alpha"}', '2026-05-24T00:00:00Z'),
                ('P31', 'PT4', 'Y', '{"tag":"beta"}',  '2026-05-24T00:00:00Z'),
                ('P32', 'PT4', 'Z', '{"tag":"gamma"}', '2026-05-24T00:00:00Z')
            """)
        }

        let results = try await IndexQuery(idx).filter([
            .or([
                .equals(propertyID: "tag", value: .select("alpha")),
                .equals(propertyID: "tag", value: .select("gamma"))
            ])
        ], in: .pageType("PT4"))

        #expect(results.count == 2)
        let ids = Set(results.map(\.id))
        #expect(ids == ["P30", "P32"])
    }

    // MARK: - Filter: exists / isNull

    @Test func filterExistsAndIsNull() async throws {
        let (dir, idx) = try await setupIndex()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await idx.dbQueue.write { db in
            try db.execute(sql: "INSERT INTO page_types(id, title, modified_at) VALUES ('PT5', 'Notes', '2026-05-24T00:00:00Z')")
            try db.execute(sql: """
                INSERT INTO pages(id, page_type_id, title, properties, modified_at) VALUES
                ('P40', 'PT5', 'WithTag',    '{"tag":"yes"}', '2026-05-24T00:00:00Z'),
                ('P41', 'PT5', 'WithoutTag', '{}',            '2026-05-24T00:00:00Z')
            """)
        }

        let existsResults = try await IndexQuery(idx).filter([
            .exists(propertyID: "tag")
        ], in: .pageType("PT5"))
        #expect(existsResults.count == 1)
        #expect(existsResults[0].id == "P40")

        let nullResults = try await IndexQuery(idx).filter([
            .isNull(propertyID: "tag")
        ], in: .pageType("PT5"))
        #expect(nullResults.count == 1)
        #expect(nullResults[0].id == "P41")
    }

    // MARK: - Sort

    @Test func sortByPropertyAscendingReturnsOrderedResults() async throws {
        let (dir, idx) = try await setupIndex()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await idx.dbQueue.write { db in
            try db.execute(sql: "INSERT INTO page_types(id, title, modified_at) VALUES ('PT6', 'Sorted', '2026-05-24T00:00:00Z')")
            try db.execute(sql: """
                INSERT INTO pages(id, page_type_id, title, properties, modified_at) VALUES
                ('P50', 'PT6', 'C-Page', '{"rank":3}', '2026-05-24T01:00:00Z'),
                ('P51', 'PT6', 'A-Page', '{"rank":1}', '2026-05-24T00:00:00Z'),
                ('P52', 'PT6', 'B-Page', '{"rank":2}', '2026-05-24T00:30:00Z')
            """)
        }

        let results = try await IndexQuery(idx).sortBy("rank", direction: .ascending, in: .pageType("PT6"))
        #expect(results.map(\.id) == ["P51", "P52", "P50"])
    }

    // MARK: - Target queries

    @Test func entitiesByTargetPageTypeReturnsAllInType() async throws {
        let (dir, idx) = try await setupIndex()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await idx.dbQueue.write { db in
            try db.execute(sql: "INSERT INTO page_types(id, title, modified_at) VALUES ('PT7', 'Library', '2026-05-24T00:00:00Z')")
            try db.execute(sql: "INSERT INTO page_types(id, title, modified_at) VALUES ('PT8', 'Other', '2026-05-24T00:00:00Z')")
            try db.execute(sql: """
                INSERT INTO pages(id, page_type_id, title, properties, modified_at) VALUES
                ('P60', 'PT7', 'BookOne',   '{}', '2026-05-24T00:00:00Z'),
                ('P61', 'PT7', 'BookTwo',   '{}', '2026-05-24T00:00:00Z'),
                ('P62', 'PT8', 'OtherPage', '{}', '2026-05-24T00:00:00Z')
            """)
        }

        let results = try await IndexQuery(idx).entitiesByTarget(.pageType("PT7"))
        #expect(results.count == 2)
        let ids = Set(results.map(\.id))
        #expect(ids == ["P60", "P61"])
        #expect(results.allSatisfy { $0.kind == .page })
    }

    // MARK: - Target queries: contextTier

    @Test func entitiesByTargetContextTierReturnsContextsForTier() async throws {
        let (dir, idx) = try await setupIndex()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await idx.dbQueue.write { db in
            // Seed contexts (tier 1)
            try db.execute(sql: """
                INSERT INTO contexts(id, tier, title) VALUES
                ('CTX1', 1, 'Space Alpha'),
                ('CTX2', 1, 'Space Beta')
            """)
        }

        let results = try await IndexQuery(idx).entitiesByTarget(.contextTier(1))
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.kind == .space })
        let titles = Set(results.map(\.title))
        #expect(titles == ["Space Alpha", "Space Beta"])
    }

    // MARK: - Move-strip count

    @Test func moveStripCountReportsDifferentPropertiesOnly() async throws {
        let (dir, idx) = try await setupIndex()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await idx.dbQueue.write { db in
            try db.execute(sql: "INSERT INTO page_types(id, title, modified_at) VALUES ('PT_SRC', 'Source', '2026-05-24T00:00:00Z')")
            try db.execute(sql: "INSERT INTO page_types(id, title, modified_at) VALUES ('PT_DST', 'Dest', '2026-05-24T00:00:00Z')")
            // Property IDs are globally unique. Move-strip identifies "shared"
            // properties by NAME (a Page keeps property values where the
            // destination has a property of the same name), not by ID.
            // Source has Alpha/Beta/Gamma; Dest has Beta/Delta. "Beta" is
            // shared by name (distinct IDs prop_B_SRC vs prop_B_DST).
            // Strip = {prop_A_SRC, prop_C_SRC} (source-only by name).
            try db.execute(sql: """
                INSERT INTO property_definitions(id, owning_type_id, owning_type_kind, name, type, modified_at) VALUES
                ('prop_A_SRC', 'PT_SRC', 'page_type', 'Alpha', 'select', '2026-05-24T00:00:00Z'),
                ('prop_B_SRC', 'PT_SRC', 'page_type', 'Beta',  'select', '2026-05-24T00:00:00Z'),
                ('prop_C_SRC', 'PT_SRC', 'page_type', 'Gamma', 'select', '2026-05-24T00:00:00Z'),
                ('prop_B_DST', 'PT_DST', 'page_type', 'Beta',  'select', '2026-05-24T00:00:00Z'),
                ('prop_D_DST', 'PT_DST', 'page_type', 'Delta', 'select', '2026-05-24T00:00:00Z')
            """)
        }

        let report = try await IndexQuery(idx).moveStripCount(
            sourceID: "PT_SRC",
            sourceKind: .pageType,
            destTypeID: "PT_DST",
            destTypeKind: .pageType
        )

        let strippedIDs = Set(report.strippedPropertyIDs)
        #expect(strippedIDs == ["prop_A_SRC", "prop_C_SRC"])
        #expect(report.strippedPropertyNames.count == 2)
        let strippedNames = Set(report.strippedPropertyNames)
        #expect(strippedNames == ["Alpha", "Gamma"])
    }

    // MARK: - Broken links

    @Test func brokenLinksDetectsDanglingTargets() async throws {
        let (dir, idx) = try await setupIndex()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await idx.dbQueue.write { db in
            // Seed two pages + one item. Then a relation pointing to a non-existent page.
            try db.execute(sql: "INSERT INTO page_types(id, title, modified_at) VALUES ('PT_BL', 'BL', '2026-05-24T00:00:00Z')")
            try db.execute(sql: """
                INSERT INTO pages(id, page_type_id, title, properties, modified_at) VALUES
                ('PBL1', 'PT_BL', 'Real Page', '{}', '2026-05-24T00:00:00Z')
            """)
            // Valid relation: PBL1 → PBL1 (self, but still valid)
            try db.execute(sql: """
                INSERT INTO relations(id, source_id, source_kind, target_id, target_kind, property_id, modified_at) VALUES
                ('R1', 'PBL1', 'page', 'PBL1',  'page', 'prop_X', '2026-05-24T00:00:00Z'),
                ('R2', 'PBL1', 'page', 'GHOST1', 'page', 'prop_Y', '2026-05-24T00:00:00Z')
            """)
        }

        let broken = try await IndexQuery(idx).brokenLinks()
        #expect(broken.count == 1)
        #expect(broken[0].relationID == "R2")
        #expect(broken[0].targetID == "GHOST1")
        #expect(broken[0].targetKind == .page)
        #expect(broken[0].sourceKind == .page)
    }

    // MARK: - Incoming relations (reverse view)

    @Test func incomingRelationsReturnsSourcesPointingAtTarget() async throws {
        let (dir, idx) = try await setupIndex()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await idx.dbQueue.write { db in
            // Two pages + one item that all point AT the shared target "TARGET1";
            // plus a fourth relation pointing elsewhere (must be excluded).
            try db.execute(sql: "INSERT INTO page_types(id, title, modified_at) VALUES ('PT_IR', 'IR', '2026-05-24T00:00:00Z')")
            try db.execute(sql: "INSERT INTO item_types(id, title, modified_at) VALUES ('IT_IR', 'IR', '2026-05-24T00:00:00Z')")
            try db.execute(sql: """
                INSERT INTO pages(id, page_type_id, title, properties, modified_at) VALUES
                ('PSRC1', 'PT_IR', 'Source Page One', '{}', '2026-05-24T00:00:00Z'),
                ('PSRC2', 'PT_IR', 'Source Page Two', '{}', '2026-05-24T00:00:00Z'),
                ('POTHER', 'PT_IR', 'Other Page',     '{}', '2026-05-24T00:00:00Z')
            """)
            try db.execute(sql: """
                INSERT INTO items(id, item_type_id, title, properties, modified_at) VALUES
                ('ISRC1', 'IT_IR', 'Source Item One', '{}', '2026-05-24T00:00:00Z')
            """)
            try db.execute(sql: """
                INSERT INTO relations(id, source_id, source_kind, target_id, target_kind, property_id, modified_at) VALUES
                ('REL1', 'PSRC1', 'page', 'TARGET1', 'unknown', 'prop_X', '2026-05-24T00:00:00Z'),
                ('REL2', 'PSRC2', 'page', 'TARGET1', 'unknown', 'prop_X', '2026-05-24T00:00:00Z'),
                ('REL3', 'ISRC1', 'item', 'TARGET1', 'unknown', 'prop_Y', '2026-05-24T00:00:00Z'),
                ('REL4', 'POTHER', 'page', 'OTHER_TARGET', 'unknown', 'prop_X', '2026-05-24T00:00:00Z')
            """)
        }

        let incoming = try await IndexQuery(idx).incomingRelations(targetID: "TARGET1")

        #expect(incoming.count == 3)
        let ids = Set(incoming.map(\.id))
        #expect(ids == ["PSRC1", "PSRC2", "ISRC1"])
        // POTHER points at a different target — must be excluded.
        #expect(!ids.contains("POTHER"))
        // Titles resolve from the source's owning table (relations carries no title).
        let byID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
        #expect(byID["PSRC1"]?.kind == .page)
        #expect(byID["PSRC1"]?.title == "Source Page One")
        #expect(byID["ISRC1"]?.kind == .item)
        #expect(byID["ISRC1"]?.title == "Source Item One")
    }
}
