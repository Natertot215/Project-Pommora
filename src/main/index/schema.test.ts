import { describe, it, expect, afterEach } from 'vitest'
import { openDb, type Db } from './db'
import { applySchema, readSchemaVersion, stampSchemaVersion, SCHEMA_VERSION } from './schema'

let db: Db | null = null
afterEach(() => {
  db?.close()
  db = null
})

const tableNames = (d: Db): string[] =>
  (d.prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").all() as { name: string }[]).map(
    (r) => r.name
  )

describe('applySchema', () => {
  it('creates all 11 tables', () => {
    db = openDb(':memory:')
    expect(db).not.toBeNull()
    if (!db) return
    applySchema(db)
    expect(tableNames(db)).toEqual([
      'agenda_events',
      'agenda_tasks',
      'connections',
      'context_links',
      'contexts',
      'meta',
      'page_collections',
      'page_sets',
      'page_types',
      'pages',
      'property_definitions'
    ])
  })

  it('is idempotent (re-apply does not throw)', () => {
    db = openDb(':memory:')
    if (!db) return
    applySchema(db)
    expect(() => applySchema(db!)).not.toThrow()
  })
})

describe('schema version', () => {
  it('is absent until stamped, then reads back the current version', () => {
    db = openDb(':memory:')
    if (!db) return
    applySchema(db)
    expect(readSchemaVersion(db)).toBeNull() // not stamped after a fresh apply
    stampSchemaVersion(db)
    expect(readSchemaVersion(db)).toBe(SCHEMA_VERSION)
  })

  it('reads null when the meta table does not exist', () => {
    db = openDb(':memory:')
    if (!db) return
    expect(readSchemaVersion(db)).toBeNull()
  })
})
