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

export function upsertCollection(
  db: Db,
  r: { id: string; title: string; icon?: string; modifiedAt: string; schemaVersion?: number },
): void {
  upsertRow(db, 'page_collections', {
    id: r.id,
    title: r.title,
    icon: r.icon ?? null,
    modified_at: r.modifiedAt,
    schema_version: r.schemaVersion ?? 1,
  })
}

/** A Set references exactly one parent: a Collection (depth-1) XOR another Set (deeper). */
export function upsertSet(
  db: Db,
  r: {
    id: string
    parentCollectionId?: string
    parentSetId?: string
    title: string
    icon?: string
    modifiedAt: string
    schemaVersion?: number
  },
): void {
  upsertRow(db, 'page_sets', {
    id: r.id,
    parent_collection_id: r.parentCollectionId ?? null,
    parent_set_id: r.parentSetId ?? null,
    title: r.title,
    icon: r.icon ?? null,
    modified_at: r.modifiedAt,
    schema_version: r.schemaVersion ?? 1,
  })
}

export function upsertPage(
  db: Db,
  r: {
    id: string
    collectionId: string
    setId?: string
    title: string
    icon?: string
    properties?: unknown
    modifiedAt: string
  },
): void {
  upsertRow(db, 'pages', {
    id: r.id,
    page_collection_id: r.collectionId,
    page_set_id: r.setId ?? null,
    title: r.title,
    icon: r.icon ?? null,
    properties: json(r.properties),
    modified_at: r.modifiedAt,
  })
}

export function upsertContext(
  db: Db,
  r: { id: string; tier: number; title: string; icon?: string },
): void {
  upsertRow(db, 'contexts', { id: r.id, tier: r.tier, title: r.title, icon: r.icon ?? null })
}

export function upsertAgendaTask(
  db: Db,
  r: {
    id: string
    title: string
    icon?: string
    dueAt?: string
    properties?: unknown
    modifiedAt: string
  },
): void {
  upsertRow(db, 'agenda_tasks', {
    id: r.id,
    title: r.title,
    icon: r.icon ?? null,
    due_at: r.dueAt ?? null,
    properties: json(r.properties),
    modified_at: r.modifiedAt,
  })
}

export function upsertAgendaEvent(
  db: Db,
  r: {
    id: string
    title: string
    icon?: string
    startAt: string
    endAt: string
    properties?: unknown
    modifiedAt: string
  },
): void {
  upsertRow(db, 'agenda_events', {
    id: r.id,
    title: r.title,
    icon: r.icon ?? null,
    start_at: r.startAt,
    end_at: r.endAt,
    properties: json(r.properties),
    modified_at: r.modifiedAt,
  })
}

export function upsertPropertyDefinition(
  db: Db,
  r: {
    id: string
    name: string
    type: string
    config?: unknown
    position: number
    modifiedAt: string
  },
): void {
  upsertRow(db, 'property_definitions', {
    id: r.id,
    name: r.name,
    type: r.type,
    config: json(r.config),
    position: r.position,
    modified_at: r.modifiedAt,
  })
}

/** Replace all context-tier links for one source (delete then insert) — Swift's reconcile. */
export function replaceContextLinks(
  db: Db,
  sourceId: string,
  links: {
    id: string
    sourceKind: string
    targetId: string
    targetKind: string
    propertyId: string
    modifiedAt: string
  }[],
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
      modified_at: l.modifiedAt,
    })
  }
}

type ConnInput = {
  id: string
  targetId?: string
  targetTitle: string
  multiplicity: number
  resolved: boolean
  modifiedAt: string
}

/** Replace one source's body connections (delete-then-insert per source). target is always a page
 *  (target_id null while phantom); source_kind + surface distinguish a page body from a block body. */
function replaceConnectionsFor(
  db: Db,
  sourceId: string,
  sourceKind: string,
  surface: string,
  conns: ConnInput[],
): void {
  db.prepare('DELETE FROM connections WHERE source_id = ?').run(sourceId)
  for (const c of conns) {
    upsertRow(db, 'connections', {
      id: c.id,
      source_id: sourceId,
      source_kind: sourceKind,
      target_id: c.targetId ?? null,
      target_kind: 'page',
      target_title: c.targetTitle,
      surface,
      multiplicity: c.multiplicity,
      weight: 1.0,
      resolved: c.resolved ? 1 : 0,
      modified_at: c.modifiedAt,
    })
  }
}

/** Replace all body connections for one page source (page-body → page). */
export function replaceConnections(db: Db, sourceId: string, conns: ConnInput[]): void {
  replaceConnectionsFor(db, sourceId, 'page', 'page_body', conns)
}

/** Replace all connections for one markdown-block source (block-body → page) — a block's `[[links]]`
 *  are first-class edges, keyed by the block's own ulid (distinct from any page id, so no collision). */
export function replaceBlockConnections(db: Db, blockId: string, conns: ConnInput[]): void {
  replaceConnectionsFor(db, blockId, 'block', 'block_body', conns)
}
