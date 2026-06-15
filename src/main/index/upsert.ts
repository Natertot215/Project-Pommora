// Per-entity index upserts — the shared write layer used by the cold build and (later)
// incremental CRUD. One generic INSERT OR REPLACE core keeps the SQL DRY; typed wrappers
// own the column mapping + the SQLite-binding conversions better-sqlite3 needs (undefined
// → null, boolean → 0/1, object → JSON TEXT). Mirrors Swift's IndexUpdater, minus the
// GRDB ceremony. Connections + context_links use replace-by-source (delete then insert),
// matching Swift's per-source reconcile.

import type { Db } from './db'

/** Generic INSERT OR REPLACE from a column→value map. Values must already be bindable. */
function upsertRow(db: Db, table: string, row: Record<string, string | number | null>): void {
  const cols = Object.keys(row)
  const sql = `INSERT OR REPLACE INTO ${table} (${cols.join(', ')}) VALUES (${cols.map(() => '?').join(', ')})`
  db.prepare(sql).run(...cols.map((c) => row[c]))
}

const json = (v: unknown): string => JSON.stringify(v ?? {})

export function upsertPageType(
  db: Db,
  r: { id: string; title: string; icon?: string; modifiedAt: string; schemaVersion?: number }
): void {
  upsertRow(db, 'page_types', {
    id: r.id,
    title: r.title,
    icon: r.icon ?? null,
    modified_at: r.modifiedAt,
    schema_version: r.schemaVersion ?? 1
  })
}

export function upsertCollection(
  db: Db,
  r: { id: string; pageTypeId: string; title: string; icon?: string; modifiedAt: string; schemaVersion?: number }
): void {
  upsertRow(db, 'page_collections', {
    id: r.id,
    page_type_id: r.pageTypeId,
    title: r.title,
    icon: r.icon ?? null,
    modified_at: r.modifiedAt,
    schema_version: r.schemaVersion ?? 1
  })
}

export function upsertSet(
  db: Db,
  r: { id: string; collectionId: string; title: string; icon?: string; modifiedAt: string; schemaVersion?: number }
): void {
  upsertRow(db, 'page_sets', {
    id: r.id,
    page_collection_id: r.collectionId,
    title: r.title,
    icon: r.icon ?? null,
    modified_at: r.modifiedAt,
    schema_version: r.schemaVersion ?? 1
  })
}

export function upsertPage(
  db: Db,
  r: {
    id: string
    pageTypeId: string
    collectionId?: string
    setId?: string
    title: string
    icon?: string
    properties?: unknown
    modifiedAt: string
  }
): void {
  upsertRow(db, 'pages', {
    id: r.id,
    page_type_id: r.pageTypeId,
    page_collection_id: r.collectionId ?? null,
    page_set_id: r.setId ?? null,
    title: r.title,
    icon: r.icon ?? null,
    properties: json(r.properties),
    modified_at: r.modifiedAt
  })
}

export function upsertContext(
  db: Db,
  r: { id: string; tier: number; title: string; icon?: string }
): void {
  upsertRow(db, 'contexts', { id: r.id, tier: r.tier, title: r.title, icon: r.icon ?? null })
}

export function upsertPropertyDefinition(
  db: Db,
  r: {
    id: string
    owningTypeId: string
    owningTypeKind: string
    name: string
    type: string
    config?: unknown
    position: number
    modifiedAt: string
  }
): void {
  upsertRow(db, 'property_definitions', {
    id: r.id,
    owning_type_id: r.owningTypeId,
    owning_type_kind: r.owningTypeKind,
    name: r.name,
    type: r.type,
    config: json(r.config),
    position: r.position,
    modified_at: r.modifiedAt
  })
}

/** Replace all context-tier links for one source (delete then insert) — Swift's reconcile. */
export function replaceContextLinks(
  db: Db,
  sourceId: string,
  links: { id: string; sourceKind: string; targetId: string; targetKind: string; propertyId: string; modifiedAt: string }[]
): void {
  db.prepare('DELETE FROM context_links WHERE source_id = ?').run(sourceId)
  for (const l of links) {
    upsertRow(db, 'context_links', {
      id: l.id,
      source_id: sourceId,
      source_kind: l.sourceKind,
      target_id: l.targetId,
      target_kind: l.targetKind,
      property_id: l.propertyId,
      modified_at: l.modifiedAt
    })
  }
}

/** Replace all body connections for one (page) source. target_id is null while phantom;
 *  source/target kind + surface are fixed (connections are page-body→page). */
export function replaceConnections(
  db: Db,
  sourceId: string,
  conns: { id: string; targetId?: string; targetTitle: string; multiplicity: number; resolved: boolean; modifiedAt: string }[]
): void {
  db.prepare('DELETE FROM connections WHERE source_id = ?').run(sourceId)
  for (const c of conns) {
    upsertRow(db, 'connections', {
      id: c.id,
      source_id: sourceId,
      source_kind: 'page',
      target_id: c.targetId ?? null,
      target_kind: 'page',
      target_title: c.targetTitle,
      surface: 'page_body',
      multiplicity: c.multiplicity,
      weight: 1.0,
      resolved: c.resolved ? 1 : 0,
      modified_at: c.modifiedAt
    })
  }
}
