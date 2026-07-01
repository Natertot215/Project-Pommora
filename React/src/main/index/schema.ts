// The index schema — the entity tables + the `meta` table. Model A (2-tier): a `page_collections`
// top tier (no parent), recursive `page_sets` keyed by parent_collection_id (depth-1) XOR
// parent_set_id (deeper), and `pages` keyed by page_collection_id (always) + a nullable
// page_set_id (null only at the Collection root). The index is REGENERATABLE — it holds no
// user data; a version mismatch drops + rebuilds. The version is stamped only AFTER a
// successful build, so a half-built index never sticks (open sees an absent version + retries).
//
// Cross-build note: the column NAMES mirror Swift's Model A so the shape is conceptually
// portable, but React's SCHEMA_VERSION is deliberately distinct from Swift's — a nexus opened
// in both apps simply rebuilds its index on each switch (safe churn, never a foreign-schema
// query). Churn-free cross-open at a matched version is a later refinement (needs Swift's exact
// DDL verified first).

import type { Db } from './db'

/** Regeneratable index version. A mismatch ⇒ drop + rebuild. Distinct from Swift's by design. */
export const SCHEMA_VERSION = 16

const META_DDL = `
  CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  );`

// The entity tables — Model A (2-tier Collection -> recursive Set).
const TABLE_DDL: string[] = [
  `CREATE TABLE IF NOT EXISTS page_collections (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    icon TEXT,
    modified_at TEXT NOT NULL,
    schema_version INTEGER NOT NULL DEFAULT 1
  );`,
  `CREATE TABLE IF NOT EXISTS page_sets (
    id TEXT PRIMARY KEY,
    parent_collection_id TEXT REFERENCES page_collections(id) ON DELETE CASCADE,
    parent_set_id TEXT REFERENCES page_sets(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    icon TEXT,
    modified_at TEXT NOT NULL,
    schema_version INTEGER NOT NULL DEFAULT 1
  );`,
  `CREATE TABLE IF NOT EXISTS pages (
    id TEXT PRIMARY KEY,
    page_collection_id TEXT NOT NULL REFERENCES page_collections(id) ON DELETE CASCADE,
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
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    config TEXT NOT NULL DEFAULT '{}',
    position INTEGER NOT NULL DEFAULT 0,
    modified_at TEXT NOT NULL
  );`
]

const INDEX_DDL = `
  CREATE INDEX IF NOT EXISTS idx_pages_page_collection_id ON pages(page_collection_id);
  CREATE INDEX IF NOT EXISTS idx_pages_page_set_id ON pages(page_set_id);
  CREATE INDEX IF NOT EXISTS idx_page_sets_parent_collection_id ON page_sets(parent_collection_id);
  CREATE INDEX IF NOT EXISTS idx_page_sets_parent_set_id ON page_sets(parent_set_id);
  CREATE INDEX IF NOT EXISTS idx_context_links_source_id ON context_links(source_id);
  CREATE INDEX IF NOT EXISTS idx_context_links_target_id ON context_links(target_id);
  CREATE INDEX IF NOT EXISTS idx_context_links_property_id ON context_links(property_id);
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
