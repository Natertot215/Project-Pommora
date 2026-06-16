// The index schema — the 10 entity tables transcribed from Swift's IndexSchema + the `meta`
// table (Swift's PommoraIndex.bootstrapMeta). The DDL + SCHEMA_VERSION are structurally
// identical to Swift's, so either app can open and query the other's index; the index is
// regeneratable, so exact row bytes (e.g. synthesized link ids) need not match. SCHEMA_VERSION
// mirrors Swift's PommoraIndex.currentSchemaVersion; an index at a different version holds no
// user data and is dropped + rebuilt. The version is stamped only AFTER a successful build,
// so a half-built index never sticks (open sees an absent version and retries).

import type { Db } from './db'

/** Must equal Swift's PommoraIndex.currentSchemaVersion. A mismatch ⇒ drop + rebuild. */
export const SCHEMA_VERSION = 14

const META_DDL = `
  CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  );`

// The 10 entity tables — verbatim from Pommora/Index/IndexSchema.swift.
const TABLE_DDL: string[] = [
  `CREATE TABLE IF NOT EXISTS page_types (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    icon TEXT,
    modified_at TEXT NOT NULL,
    schema_version INTEGER NOT NULL DEFAULT 1
  );`,
  `CREATE TABLE IF NOT EXISTS page_collections (
    id TEXT PRIMARY KEY,
    page_type_id TEXT NOT NULL REFERENCES page_types(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    icon TEXT,
    modified_at TEXT NOT NULL,
    schema_version INTEGER NOT NULL DEFAULT 1
  );`,
  `CREATE TABLE IF NOT EXISTS page_sets (
    id TEXT PRIMARY KEY,
    page_collection_id TEXT NOT NULL REFERENCES page_collections(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    icon TEXT,
    modified_at TEXT NOT NULL,
    schema_version INTEGER NOT NULL DEFAULT 1
  );`,
  `CREATE TABLE IF NOT EXISTS pages (
    id TEXT PRIMARY KEY,
    page_type_id TEXT NOT NULL REFERENCES page_types(id) ON DELETE CASCADE,
    page_collection_id TEXT REFERENCES page_collections(id) ON DELETE SET NULL,
    page_set_id TEXT REFERENCES page_sets(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    icon TEXT,
    properties TEXT NOT NULL DEFAULT '{}',
    modified_at TEXT NOT NULL
  );`,
  `CREATE TABLE IF NOT EXISTS agenda_tasks (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    icon TEXT,
    due_at TEXT,
    properties TEXT NOT NULL DEFAULT '{}',
    modified_at TEXT NOT NULL
  );`,
  `CREATE TABLE IF NOT EXISTS agenda_events (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    icon TEXT,
    start_at TEXT NOT NULL,
    end_at TEXT NOT NULL,
    properties TEXT NOT NULL DEFAULT '{}',
    modified_at TEXT NOT NULL
  );`,
  `CREATE TABLE IF NOT EXISTS contexts (
    id TEXT PRIMARY KEY,
    tier INTEGER NOT NULL,
    title TEXT NOT NULL,
    icon TEXT
  );`,
  `CREATE TABLE IF NOT EXISTS context_links (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    target_id TEXT NOT NULL,
    target_kind TEXT NOT NULL,
    property_id TEXT NOT NULL,
    modified_at TEXT NOT NULL
  );`,
  `CREATE TABLE IF NOT EXISTS connections (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    target_id TEXT,
    target_kind TEXT NOT NULL,
    target_title TEXT NOT NULL,
    surface TEXT NOT NULL,
    multiplicity INTEGER NOT NULL DEFAULT 1,
    weight REAL NOT NULL DEFAULT 1.0,
    resolved INTEGER NOT NULL DEFAULT 0,
    modified_at TEXT NOT NULL
  );`,
  `CREATE TABLE IF NOT EXISTS property_definitions (
    id TEXT PRIMARY KEY,
    owning_type_id TEXT NOT NULL,
    owning_type_kind TEXT NOT NULL,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    config TEXT NOT NULL DEFAULT '{}',
    position INTEGER NOT NULL DEFAULT 0,
    modified_at TEXT NOT NULL
  );`
]

// ~14 indexes — verbatim from IndexSchema.swift.
const INDEX_DDL = `
  CREATE INDEX IF NOT EXISTS idx_pages_page_type_id ON pages(page_type_id);
  CREATE INDEX IF NOT EXISTS idx_pages_page_collection_id ON pages(page_collection_id);
  CREATE INDEX IF NOT EXISTS idx_pages_page_set_id ON pages(page_set_id);
  CREATE INDEX IF NOT EXISTS idx_page_collections_page_type_id ON page_collections(page_type_id);
  CREATE INDEX IF NOT EXISTS idx_page_sets_page_collection_id ON page_sets(page_collection_id);
  CREATE INDEX IF NOT EXISTS idx_context_links_source_id ON context_links(source_id);
  CREATE INDEX IF NOT EXISTS idx_context_links_target_id ON context_links(target_id);
  CREATE INDEX IF NOT EXISTS idx_context_links_property_id ON context_links(property_id);
  CREATE INDEX IF NOT EXISTS idx_property_definitions_owning_type ON property_definitions(owning_type_id, owning_type_kind);
  CREATE INDEX IF NOT EXISTS idx_contexts_tier ON contexts(tier);
  CREATE INDEX IF NOT EXISTS idx_connections_source_id ON connections(source_id);
  CREATE INDEX IF NOT EXISTS idx_connections_target_id ON connections(target_id);
  CREATE INDEX IF NOT EXISTS idx_connections_target_title ON connections(target_kind, target_title);
  CREATE INDEX IF NOT EXISTS idx_pages_title ON pages(title COLLATE NOCASE);`

/** Create the meta table + all entity tables + indexes (idempotent: IF NOT EXISTS). */
export function applySchema(db: Db): void {
  db.exec(META_DDL)
  for (const ddl of TABLE_DDL) db.exec(ddl)
  db.exec(INDEX_DDL)
}

/** The stored schema version, or null if the meta table / row is absent (⇒ rebuild). */
export function readSchemaVersion(db: Db): number | null {
  const hasMeta = db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='meta'").get()
  if (!hasMeta) return null
  const row = db.prepare("SELECT value FROM meta WHERE key = 'schema_version'").get() as
    | { value: string }
    | undefined
  if (!row) return null
  const n = Number(row.value)
  return Number.isFinite(n) ? n : null
}

/** Stamp the DB as fully populated at SCHEMA_VERSION. Call ONLY after a successful build —
 *  until then open() sees an absent version and rebuilds (no half-built index sticks). */
export function stampSchemaVersion(db: Db): void {
  db.prepare("INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', ?)").run(String(SCHEMA_VERSION))
}
