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
    // v4 (2026-05-29): denormalize entity icon into the per-entity tables
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
    // v6 (2026-05-30): denormalize per-Collection `icon` into the
    // collection tables (#45) so the relation picker's
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
    // v8 (2026-06-05): add the `connections` table (inline-link edges scanned
    // from bodies) + idx_connections_* + title indexes.
    // Net-new derived data; bumping 7 → 8 forces one rebuild so
    // existing DBs gain the table and IndexBuilder backfills connections from
    // on-disk bodies. No user data at risk (regeneratable index).
    //
    // v9 (2026-06-06): launch index scan switched from strict PageFile.load to
    // lenient PageFile.loadLenient (IndexBuilder.collectPagesInFolder), so adopted
    // `.md` Pages lacking Pommora frontmatter are indexed + title-resolvable from
    // launch instead of only after an incidental CRUD write opened them. Existing
    // v8 DBs were built by the strict scan and are MISSING every frontmatter-less
    // Page, so [[ ]] links to them render unresolved. Bumping 8 → 9 forces
    // one delete+rebuild so those Pages enter the index. No user data at risk
    // (regeneratable index).
    //
    // v10 (2026-06-06): launch scan now honors the user folder-exclusion veto at
    // the FILE level (IndexBuilder.collectPagesInFolder applies
    // FolderFilter.isExcluded, matching loadAll's descendantFiles). The lenient v9
    // scan had pulled excluded content (e.g. loose meta files like CLAUDE.md) into
    // the index because it ignored excluded_folders for files. Bumping 9 → 10 forces
    // one delete+rebuild so excluded content is dropped. No user data at risk.
    //
    // v11 (2026-06-09): PagesV2 P7 — the index becomes page-only: the three
    // legacy second-entity tables (and their indexes) are dropped from the
    // schema, and connections/context_links are page-only.
    // Bumping 10 → 11 marks every pre-v11 DB stale so `open(at:)` deletes +
    // recreates it page-only on open (no data migration — the index is
    // regeneratable); any orphaned legacy rows lingering in connections or
    // context_links vanish with the rebuild.
    //
    // v12: Contexts Decoupling — contexts.parent_topic_id dropped (free-standing tiers); delete+rebuild on open, no data migration.
    //
    // v13: Space→Area rename — kind strings; rebuild re-stamps rows. The tier-1
    // entity-kind string changed from "space" to "area" (EntityKind raw + the
    // kindTableMap/RelationTargetKind lookups), so persisted state.json refs and
    // every "area" row in context_links/contexts re-derive on rebuild. Bumping
    // 12 → 13 forces one delete+rebuild on open; no data migration (regeneratable).
    //
    // v14: Page Sets — new `page_sets` table (sub-folders inside a Collection
    // carrying `_pageset.json`) + `pages.page_set_id` FK column. Bumping
    // 13 → 14 forces one delete+rebuild so existing DBs gain the table/column
    // and IndexBuilder backfills sets from the sidecars. No data migration
    // (regeneratable).
    //
    // v15: recursive page_sets — depth-1 via parent_type_id, deeper via parent_set_id.
    // `page_sets` now has `parent_type_id` (nullable FK→page_types) and `parent_set_id`
    // (nullable self-ref FK→page_sets) instead of the old `page_collection_id`; exactly
    // one of the two is non-null per row. `set_order` column added. `page_collections`
    // table remains in the schema as a vestigial stub (Phase-2 task 2.4 drops/renames
    // it); nothing writes to it from v15 onward. IndexBuilder walks sets recursively at
    // any depth. Bumping 14 → 15 forces one delete+rebuild. No data migration.
    //
    // v16: page_types→page_collections rename; vestigial page_collections stub dropped;
    // page_sets.parent_type_id→parent_collection_id; pages cleaned to two container
    // columns (page_collection_id FK→page_collections, page_set_id FK→page_sets).
    static let currentSchemaVersion: Int = 16

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
        let nexusDir = nexusRoot.appendingPathComponent(".nexus")
        try FileManager.default.createDirectory(at: nexusDir, withIntermediateDirectories: true)

        let dbURL = nexusDir.appendingPathComponent("index.db")

        let isNew = !FileManager.default.fileExists(atPath: dbURL.path)

        // Existing file: read meta.schema_version. Mismatch or corruption (SQLite
        // error opening) → delete + recurse to recreate fresh.
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
                }
                // Version mismatch — dbQueue deallocated here; fall through to delete + recreate.
            } catch {
                // Corruption — fall through to delete + recreate.
            }
            try? FileManager.default.removeItem(at: dbURL)
            return try open(at: nexusRoot)
        }

        let dbQueue = try DatabaseQueue(path: dbURL.path)
        try dbQueue.write { db in
            try bootstrapMeta(db)
            try IndexSchema.apply(to: db)
        }

        // needsRebuild = true on fresh-create.
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
