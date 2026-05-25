import Foundation
import GRDB

/// Per-Nexus SQLite index DB (regeneratable — no user data). Backs the
/// Notion-style filter query API + relation picker + broken-links surface.
/// Stored at `<nexus>/.nexus/index.db`. Schema version bumps force a full
/// rebuild via IndexBuilder (Phase E.4).
final class PommoraIndex {
    static let currentSchemaVersion: Int = 1

    let dbQueue: DatabaseQueue   // GRDB connection pool (serialized writes, concurrent reads)
    let dbURL: URL

    private init(dbQueue: DatabaseQueue, dbURL: URL) {
        self.dbQueue = dbQueue
        self.dbURL = dbURL
    }

    /// Opens (creating if necessary) the per-nexus index DB. If the existing DB's
    /// schema_version differs from `currentSchemaVersion`, the file is deleted
    /// and a fresh empty DB is created — caller must signal "rebuild needed" to
    /// the index builder. Returns the connection + the rebuild signal.
    static func open(at nexusRoot: URL) throws -> (index: PommoraIndex, needsRebuild: Bool) {
        // 1. Ensure .nexus dir exists.
        let nexusDir = nexusRoot.appendingPathComponent(".nexus")
        try FileManager.default.createDirectory(at: nexusDir, withIntermediateDirectories: true)

        // 2. Compute dbURL = nexusRoot/.nexus/index.db.
        let dbURL = nexusDir.appendingPathComponent("index.db")

        let isNew = !FileManager.default.fileExists(atPath: dbURL.path)

        // 3. If file exists: open + read meta.schema_version. If mismatch → close + delete + recurse.
        //    On corruption (SQLite error opening) → delete + recurse.
        if !isNew {
            do {
                let dbQueue = try DatabaseQueue(path: dbURL.path)
                let versionString = try dbQueue.read { db -> String? in
                    // If meta table doesn't exist yet, treat as mismatch.
                    guard try db.tableExists("meta") else { return nil }
                    return try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'schema_version'")
                }
                let storedVersion = versionString.flatMap { Int($0) }
                if storedVersion == currentSchemaVersion {
                    return (PommoraIndex(dbQueue: dbQueue, dbURL: dbURL), false)
                } else {
                    // Version mismatch — close (dealloc) and delete.
                }
                // dbQueue deallocated here; fall through to delete + recreate.
            } catch {
                // Corruption — fall through to delete + recreate.
            }
            try? FileManager.default.removeItem(at: dbURL)
            // Recurse to create a fresh DB.
            return try open(at: nexusRoot)
        }

        // 4. File is new: open, bootstrap meta table + write schema_version, apply schema.
        let dbQueue = try DatabaseQueue(path: dbURL.path)
        try dbQueue.write { db in
            try bootstrapMeta(db)
            try IndexSchema.apply(to: db)
        }

        // 5. Return (index, needsRebuild). needsRebuild = true on fresh-create.
        return (PommoraIndex(dbQueue: dbQueue, dbURL: dbURL), true)
    }

    private static func bootstrapMeta(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
        """)
        try db.execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', ?);", arguments: [String(currentSchemaVersion)])
    }
}
