import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { openDb, type Db } from './db'
import { applySchema } from './schema'
import {
  upsertCollection,
  upsertSet,
  upsertPage,
  upsertContext,
  upsertPropertyDefinition,
  replaceContextLinks,
  replaceConnections
} from './upsert'

let db: Db
beforeEach(() => {
  const d = openDb(':memory:')
  if (!d) throw new Error('open failed')
  db = d
  applySchema(db)
})
afterEach(() => db.close())

const one = (sql: string, ...args: unknown[]): Record<string, unknown> =>
  db.prepare(sql).get(...args) as Record<string, unknown>
const count = (table: string, where = '', ...args: unknown[]): number =>
  (db.prepare(`SELECT COUNT(*) c FROM ${table} ${where}`).get(...args) as { c: number }).c

describe('entity upserts', () => {
  it('writes the collection→set→sub-set→page hierarchy (Model A) with JSON properties', () => {
    upsertCollection(db, { id: 'co', title: 'Coll', modifiedAt: 'M' })
    upsertSet(db, { id: 'se', parentCollectionId: 'co', title: 'Set', modifiedAt: 'M' })
    upsertSet(db, { id: 'sub', parentSetId: 'se', title: 'SubSet', modifiedAt: 'M' })
    upsertPage(db, {
      id: 'pg',
      collectionId: 'co',
      setId: 'sub',
      title: 'Page',
      properties: { prop_x: { $status: 'todo' } },
      modifiedAt: 'M'
    })
    const set = one('SELECT * FROM page_sets WHERE id = ?', 'se')
    expect(set.parent_collection_id).toBe('co')
    expect(set.parent_set_id).toBeNull()
    const sub = one('SELECT * FROM page_sets WHERE id = ?', 'sub')
    expect(sub.parent_set_id).toBe('se')
    expect(sub.parent_collection_id).toBeNull()
    const row = one('SELECT * FROM pages WHERE id = ?', 'pg')
    expect(row.page_collection_id).toBe('co')
    expect(row.page_set_id).toBe('sub')
    expect(JSON.parse(row.properties as string)).toEqual({ prop_x: { $status: 'todo' } })
  })

  it('is INSERT OR REPLACE (same id ⇒ one row, latest wins)', () => {
    upsertCollection(db, { id: 'co', title: 'Old', modifiedAt: 'M' })
    upsertCollection(db, { id: 'co', title: 'New', modifiedAt: 'M2' })
    expect(count('page_collections')).toBe(1)
    expect(one('SELECT title FROM page_collections WHERE id = ?', 'co').title).toBe('New')
  })

  it('writes contexts + property definitions', () => {
    upsertContext(db, { id: 'cx', tier: 1, title: 'Area' })
    upsertPropertyDefinition(db, {
      id: 'prop_x',
      owningTypeId: 'co',
      owningTypeKind: 'page_collection',
      name: 'Score',
      type: 'number',
      position: 0,
      modifiedAt: 'M'
    })
    expect(one('SELECT tier FROM contexts WHERE id = ?', 'cx').tier).toBe(1)
    expect(one('SELECT type FROM property_definitions WHERE id = ?', 'prop_x').type).toBe('number')
  })
})

describe('replace-by-source', () => {
  it('replaceContextLinks swaps one source without touching another', () => {
    replaceContextLinks(db, 'p1', [
      { id: 'l1', sourceKind: 'page', targetId: 'cxA', targetKind: 'context', propertyId: '_tier1', modifiedAt: 'M' },
      { id: 'l2', sourceKind: 'page', targetId: 'cxB', targetKind: 'context', propertyId: '_tier1', modifiedAt: 'M' }
    ])
    replaceContextLinks(db, 'p2', [
      { id: 'l3', sourceKind: 'page', targetId: 'cxA', targetKind: 'context', propertyId: '_tier1', modifiedAt: 'M' }
    ])
    // Re-sync p1 down to a single link.
    replaceContextLinks(db, 'p1', [
      { id: 'l1', sourceKind: 'page', targetId: 'cxA', targetKind: 'context', propertyId: '_tier1', modifiedAt: 'M' }
    ])
    expect(count('context_links', 'WHERE source_id = ?', 'p1')).toBe(1)
    expect(count('context_links', 'WHERE source_id = ?', 'p2')).toBe(1) // untouched
  })

  it('replaceConnections stores phantom (null target, resolved 0) + resolved (1)', () => {
    replaceConnections(db, 'p1', [
      { id: 'c1', targetTitle: 'ghost', multiplicity: 2, resolved: false, modifiedAt: 'M' },
      { id: 'c2', targetId: 'p9', targetTitle: 'real', multiplicity: 1, resolved: true, modifiedAt: 'M' }
    ])
    const ghost = one('SELECT * FROM connections WHERE id = ?', 'c1')
    expect(ghost.target_id).toBeNull()
    expect(ghost.resolved).toBe(0)
    expect(ghost.multiplicity).toBe(2)
    const real = one('SELECT * FROM connections WHERE id = ?', 'c2')
    expect(real.target_id).toBe('p9')
    expect(real.resolved).toBe(1)

    replaceConnections(db, 'p1', []) // re-sync to none
    expect(count('connections', 'WHERE source_id = ?', 'p1')).toBe(0)
  })
})
