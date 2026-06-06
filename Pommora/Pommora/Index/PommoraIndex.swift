import Foundation
import GRDB
import Observation

/// Per-Nexus SQLite index DB (regeneratable — no user data). Backs the
/// Notion-style filter query API + relation picker + broken-links surface.
/// Stored at `<nexus>/.nexus/index.db`. Schema version bumps force a full
/// rebuild via IndexBuilder (Phase E.4).
///
/// `@Observable` makes the class injectable via `@Environment(PommoraIndex.self)`.
/// It carries no `var` state, so observation tracks nothing — env-injectability
/// is the sole goal. The macro adds a mutable `ObservationRegistrar` (itself
/// `Sendable`), which drops the implicit all-`let` class Sendability the type
/// previously relied on; we restore it with an explicit `@unchecked Sendable`
/// conformance. Safe: the registrar is `Sendable`, the only shared mutable
/// state (the GRDB `DatabaseQueue`) is internally serialized, and the class is
/// accessed from async GRDB read/write closures — so it stays actor-free
/// (no `@MainActor`).
@Observable
final class PommoraIndex: @unchecked Sendable {
    // v2 (2026-05-27): bumped on the Folders revert. v1 dev databases created
    // during the Folders era carry a now-dormant `folders` table + a
    // `page_folder_id` column on `pages` (the schema added them via
    // CREATE-IF-NOT-EXISTS without a version bump). Bumping to 2 marks every
    // v1 DB stale so `open(at:)` deletes + recreates it fresh from the
    // folders-free schema; IndexBuilder repopulates. Safe — the index holds no
    // user data.
    //
    // v3 (2026-05-29): Relations Redesign. Tier values (`_tier1/2/3`) emit into
    // the `context_links` table so the Context-delete cascade's reverse query
    // (`IndexQuery.incomingContextLinks`) can see tier→Context links. A v2 DB built
    // before that change has no tier rows in `context_links` for
    // un-edited entities, so the cascade would silently miss them. Bumping to 3
    // forces every existing DB through one delete+rebuild, which backfills tiers
    // into `context_links` via the updated IndexBuilder. Same throwaway-cache rationale
    // as v2 — no user data is at risk. (This is the INDEX-DB version; distinct from
    // the per-Type sidecar `schemaVersion` migrated by adoption.)
    //
    // v4 (2026-05-29): denormalize entity icon into pages/items/contexts/agenda_*
    // so relation values resolve to icon+title from the index.
    //
    // v5 (2026-05-29): rebuild-resilience fix. The prior flow stamped
    // schema_version during open() *before* IndexBuilder.populate ran, and
    // populate was all-or-nothing — one bad on-disk row (a duplicate-id page
    // from a legacy collision, an orphaned FK) rolled the WHOLE rebuild back,
    // leaving the index (and its Contexts) empty while the version was already
    // persisted, so no relaunch ever retried. The fix (a) skips+logs bad rows
    // instead of rolling the rebuild back, and (b) defers the schema_version
    // stamp until populate succeeds (`markSchemaVersionCurrent()`). Bumping
    // 4 → 5 forces any index left stuck-empty at v4 through one clean rebuild.
    //
    // v6 (2026-05-30): denormalize per-Collection/Set `icon` into the
    // page_collections / item_collections tables (#45) so the relation picker's
    // grouped query returns each container's icon. The sidecar JSON stays the
    // source of truth; this column is the regeneratable fast copy. Bumping
    // 5 → 6 forces one rebuild so existing indexes gain the new column and
    // backfill icons from the sidecars via IndexBuilder.
    //
    // v7 (2026-06-05): rename `relations` table → `context_links` + indexes
    // `idx_relations_*` → `idx_context_links_*`. Pure DDL rename; no data-model
    // change. Bumping 6 → 7 forces one rebuild so existing databases are
    // recreated with the renamed table.
    //
    // v8 (2026-06-05): add the `connections` table (inline-link edges scanned from
    // Page/Item bodies — [[ ]]/{{ }}) + idx_connections_* + title indexes on
    // pages/items. Net-new derived data; bumping 7 → 8 forces one rebuild so
    // existing DBs gain the table and IndexBuilder backfills connections from
    // on-disk bodies. No user data at risk (regeneratable index).
    //
    // v9 (2026-06-06): launch index scan switched from strict PageFile.load to
    // lenient PageFile.loadLenient (IndexBuilder.collectPagesInFolder), so adopted
    // `.md` Pages lacking Pommora frontmatter are indexed + title-resolvable from
    // launch instead of only after an incidental CRUD write opened them. Existing
    // v8 DBs were built by the strict scan and are MISSING every frontmatter-less
    // Page, so [[ ]]/{{ }} links to them render unresolved. Bumping 8 → 9 forces
    // one delete+rebuild so those Pages enter the index. No user data at risk
    // (regeneratable index).
    static let currentSchemaVersion: Int = 9

    let dbQueue: DatabaseQueue  // GRDB connection pool (serialized writes, concurrent reads)
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
        try db.execute(
            sql: """
                    CREATE TABLE IF NOT EXISTS meta (
                        key TEXT PRIMARY KEY,
                        value TEXT NOT NULL
                    );
                """)
        // NOTE: schema_version is intentionally NOT stamped here. A fresh DB is
        // returned with needsRebuild = true; the caller stamps the version via
        // `markSchemaVersionCurrent()` only AFTER `IndexBuilder.populate`
        // succeeds. So a failed/rolled-back rebuild leaves the version absent
        // and the next launch retries — instead of locking in an empty index.
    }

    /// Stamps the DB as fully populated at `currentSchemaVersion`. Call only
    /// after a successful `IndexBuilder.populate` (or when no populate is
    /// needed). Until this is written, `open(at:)` sees an absent/stale version
    /// and rebuilds — the guard that stops a half-built index from sticking.
    func markSchemaVersionCurrent() throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', ?);",
                arguments: [String(Self.currentSchemaVersion)]
            )
        }
    }
}
