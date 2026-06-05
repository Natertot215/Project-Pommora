import GRDB
import Testing
@testable import Pommora

@Suite struct ConnectionSchemaTests {
    @Test func connectionsTableAndIndexesExist() throws {
        let q = try DatabaseQueue()
        try q.write { try IndexSchema.apply(to: $0) }
        try q.read { db in
            #expect(try db.tableExists("connections"))
            let cols = try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('connections')")
            for c in ["id", "source_id", "source_kind", "target_id", "target_kind",
                      "target_title", "surface", "multiplicity", "weight", "resolved", "modified_at"] {
                #expect(cols.contains(c))
            }
        }
    }

    @Test func schemaVersionIsEight() { #expect(PommoraIndex.currentSchemaVersion == 8) }
}
