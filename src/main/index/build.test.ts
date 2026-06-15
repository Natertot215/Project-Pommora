import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, mkdir } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { rebuildIndex } from './build'
import { writeJson } from '../io/atomicWrite'
import { nexusDir, nexusConfig, NEXUS_CONFIG_FILES, contextTierDir } from '../paths'
import { createFolderEntity } from '../crud/folderEntity'
import { addProperty } from '../crud/schema'
import { createPage, updatePageProperty, setPageTier } from '../crud/page'
import type { Db } from './db'
import type { PropertyDefinition } from '@shared/properties'

let root: string
const ids: { type?: string; score?: string; a?: string; b?: string; work?: string } = {}

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-index-build-'))
  // nexus.json ⇒ sidecar mode (stable ids from sidecars).
  await mkdir(nexusDir(root), { recursive: true })
  await writeJson(nexusConfig(root, NEXUS_CONFIG_FILES.identity), { id: 'nx', created_at: '2026-01-01T00:00:00.000Z' })

  const type = await createFolderEntity(root, 'pageType', 'Notes')
  if (!type.ok) throw new Error('setup: type')
  ids.type = type.value.id
  const score = await addProperty(type.value.path, { id: '', name: 'Score', type: 'number' } as PropertyDefinition)
  if (!score.ok) throw new Error('setup: prop')
  ids.score = score.value.id

  const a = await createPage(type.value.path, 'PageA', { body: 'see [[PageB]]' })
  const b = await createPage(type.value.path, 'PageB')
  if (!a.ok || !b.ok) throw new Error('setup: pages')
  ids.a = a.value.id
  ids.b = b.value.id
  await updatePageProperty(a.value.path, ids.score, { kind: 'number', value: 5 })

  const work = await createFolderEntity(contextTierDir(root, 'areas'), 'area', 'Work', { tier: 1 })
  if (!work.ok) throw new Error('setup: area')
  ids.work = work.value.id
  await setPageTier(a.value.path, 1, [ids.work])
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

const get = (db: Db, sql: string, ...a: unknown[]) => db.prepare(sql).get(...a) as Record<string, unknown> | undefined

describe('rebuildIndex (cold build)', () => {
  it('populates every table from the canonical files', async () => {
    const db = await rebuildIndex(root)
    expect(db).not.toBeNull()
    if (!db) return

    // Structure
    expect(get(db, 'SELECT title FROM page_types WHERE id = ?', ids.type)?.title).toBe('Notes')
    expect((get(db, 'SELECT COUNT(*) c FROM pages') as { c: number }).c).toBe(2)

    // Page properties (number encoded bare)
    const a = get(db, 'SELECT properties FROM pages WHERE id = ?', ids.a)
    expect(JSON.parse(a?.properties as string)[ids.score!]).toBe(5)

    // Property definition
    const def = get(db, 'SELECT name, type FROM property_definitions WHERE id = ?', ids.score)
    expect(def).toMatchObject({ name: 'Score', type: 'number' })

    // Context (tier 1)
    expect(get(db, 'SELECT tier, title FROM contexts WHERE id = ?', ids.work)).toMatchObject({ tier: 1, title: 'Work' })

    // Resolved connection PageA → PageB
    const conn = get(db, 'SELECT * FROM connections WHERE source_id = ?', ids.a)
    expect(conn).toMatchObject({ target_title: 'pageb', target_id: ids.b, resolved: 1 })

    // Tier context link PageA → Work
    const link = get(db, 'SELECT * FROM context_links WHERE source_id = ?', ids.a)
    expect(link).toMatchObject({ target_id: ids.work, property_id: '_tier1' })

    db.close()
  })

  it('reuses the stamped index on a second open (no rebuild)', async () => {
    const first = await rebuildIndex(root)
    first?.close()
    const second = await rebuildIndex(root)
    expect(second).not.toBeNull()
    // Data still present ⇒ it reused rather than wiping + rebuilding empty.
    expect(second && (get(second, 'SELECT COUNT(*) c FROM pages') as { c: number }).c).toBe(2)
    second?.close()
  })
})
