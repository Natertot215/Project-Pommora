import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { openIndex } from './open'
import { stampSchemaVersion } from './schema'
import type { Db } from './db'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-index-open-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

const seedCollection = (db: Db, id: string) =>
  db
    .prepare(
      "INSERT INTO page_collections (id, title, modified_at) VALUES (?, 'T', '2026-01-01T00:00:00Z')",
    )
    .run(id)
const collectionIds = (db: Db) =>
  (db.prepare('SELECT id FROM page_collections').all() as { id: string }[]).map((r) => r.id)

describe('openIndex', () => {
  it('creates a fresh DB needing a rebuild, then reuses it once stamped', () => {
    const first = openIndex(root)
    expect(first?.needsRebuild).toBe(true)
    if (!first) return
    seedCollection(first.db, 't1')
    stampSchemaVersion(first.db)
    first.db.close()

    const second = openIndex(root)
    expect(second?.needsRebuild).toBe(false) // reused
    expect(second && collectionIds(second.db)).toEqual(['t1']) // data intact
    second?.db.close()
  })

  it('deletes + recreates on a version mismatch, dropping stale data', () => {
    const first = openIndex(root)
    if (!first) return
    seedCollection(first.db, 'stale')
    // Stamp a WRONG version (simulating an older Pommora build).
    first.db
      .prepare("INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', '1')")
      .run()
    first.db.close()

    const second = openIndex(root)
    expect(second?.needsRebuild).toBe(true) // reset
    expect(second && collectionIds(second.db)).toEqual([]) // stale data gone
    second?.db.close()
  })

  it('rebuilds when the version was never stamped (half-built index)', () => {
    const first = openIndex(root)
    if (!first) return
    seedCollection(first.db, 'half')
    first.db.close() // never stamped

    const second = openIndex(root)
    expect(second?.needsRebuild).toBe(true)
    second?.db.close()
  })
})
