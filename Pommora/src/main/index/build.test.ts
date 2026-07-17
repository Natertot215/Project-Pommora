import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, mkdir, writeFile, utimes } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { rebuildIndex } from './build'
import { blockFilePath } from '../blocks'
import { writeJson } from '../io/atomicWrite'
import { nexusDir, nexusConfig, NEXUS_CONFIG_FILES, contextTierDir, blockHostDir } from '../paths'
import { createFolderEntity } from '../crud/folderEntity'
import { createProperty } from '../crud/registryProperty'
import { assignProperty } from '../crud/assignment'
import { createPage, updatePageProperty, setPageTier } from '../crud/page'
import { createAgendaItem, setAgendaTier, updateAgendaProperty } from '../crud/agendaEntity'
import { defaultStatusSeed, type PropertyDefinition } from '@shared/properties'
import type { Db } from './db'

let root: string
const ids: {
  collection?: string
  score?: string
  set?: string
  setPage?: string
  a?: string
  b?: string
  work?: string
  task?: string
} = {}

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-index-build-'))
  // nexus.json ⇒ sidecar mode (stable ids from sidecars).
  await mkdir(nexusDir(root), { recursive: true })
  await writeJson(nexusConfig(root, NEXUS_CONFIG_FILES.identity), {
    id: 'nx',
    created_at: '2026-01-01T00:00:00.000Z',
  })

  // 2-tier Model A fixture: a Collection (schema-bearing) with two root pages + a depth-1 Set
  // holding one page (exercises page_sets.parent_collection_id + pages.page_set_id).
  const coll = await createFolderEntity(root, 'collection', 'Notes')
  if (!coll.ok) throw new Error('setup: collection')
  ids.collection = coll.value.id
  const score = await createProperty(root, {
    id: '',
    name: 'Score',
    type: 'number',
  } as PropertyDefinition)
  if (!score.ok) throw new Error('setup: prop')
  ids.score = score.value.id
  await assignProperty(root, coll.value.path, ids.score)

  const a = await createPage(coll.value.path, 'PageA', { body: 'see [[PageB]] and [[PageA]]' })
  const b = await createPage(coll.value.path, 'PageB')
  if (!a.ok || !b.ok) throw new Error('setup: pages')
  ids.a = a.value.id
  ids.b = b.value.id
  await updatePageProperty(a.value.path, ids.score, { kind: 'number', value: 5 })

  const daily = await createFolderEntity(coll.value.path, 'set', 'Daily', {
    parent_id: ids.collection,
  })
  if (!daily.ok) throw new Error('setup: set')
  ids.set = daily.value.id
  const sp = await createPage(daily.value.path, 'Entry')
  if (!sp.ok) throw new Error('setup: setpage')
  ids.setPage = sp.value.id

  const work = await createFolderEntity(contextTierDir(root, 'areas'), 'area', 'Work', { tier: 1 })
  if (!work.ok) throw new Error('setup: area')
  ids.work = work.value.id
  await setPageTier(a.value.path, 1, [ids.work])

  // Agenda: a Tasks folder (config seeded with built-in _status) + one task.
  const tasksCfg = await createFolderEntity(root, 'taskConfig', 'Tasks', {
    property_definitions: [
      { id: '_status', name: 'Status', type: 'status', status_groups: defaultStatusSeed() },
    ],
    schema_version: 1,
  })
  if (!tasksCfg.ok) throw new Error('setup: taskconfig')
  const task = await createAgendaItem(tasksCfg.value.path, 'task', 'Buy milk', {
    due_at: '2026-06-20T00:00:00.000Z',
  })
  if (!task.ok) throw new Error('setup: task')
  ids.task = task.value.id
  await updateAgendaProperty(task.value.path, '_status', { kind: 'status', value: 'not_started' })
  await setAgendaTier(task.value.path, 1, [ids.work])
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

const get = (db: Db, sql: string, ...a: unknown[]) =>
  db.prepare(sql).get(...a) as Record<string, unknown> | undefined

describe('rebuildIndex (cold build)', () => {
  it('populates every table from the canonical files', async () => {
    const db = await rebuildIndex(root)
    expect(db).not.toBeNull()
    if (!db) return

    // Structure (Model A)
    expect(get(db, 'SELECT title FROM page_collections WHERE id = ?', ids.collection)?.title).toBe(
      'Notes',
    )
    expect((get(db, 'SELECT COUNT(*) c FROM pages') as { c: number }).c).toBe(3)
    // The depth-1 Set references its Collection; its page records both ids; a root page has no set.
    expect(
      get(db, 'SELECT parent_collection_id, parent_set_id FROM page_sets WHERE id = ?', ids.set),
    ).toMatchObject({
      parent_collection_id: ids.collection,
      parent_set_id: null,
    })
    expect(
      get(db, 'SELECT page_collection_id, page_set_id FROM pages WHERE id = ?', ids.setPage),
    ).toMatchObject({
      page_collection_id: ids.collection,
      page_set_id: ids.set,
    })
    expect(
      get(db, 'SELECT page_collection_id, page_set_id FROM pages WHERE id = ?', ids.a),
    ).toMatchObject({
      page_collection_id: ids.collection,
      page_set_id: null,
    })

    // Page properties (number encoded bare)
    const a = get(db, 'SELECT properties FROM pages WHERE id = ?', ids.a)
    expect(JSON.parse(a?.properties as string)[ids.score!]).toBe(5)

    // Property definition
    const def = get(db, 'SELECT name, type FROM property_definitions WHERE id = ?', ids.score)
    expect(def).toMatchObject({ name: 'Score', type: 'number' })

    // Context (tier 1)
    expect(get(db, 'SELECT tier, title FROM contexts WHERE id = ?', ids.work)).toMatchObject({
      tier: 1,
      title: 'Work',
    })

    // Resolved connection PageA → PageB; the self-link [[PageA]] is skipped (Swift parity)
    const conns = db.prepare('SELECT * FROM connections WHERE source_id = ?').all(ids.a) as Record<
      string,
      unknown
    >[]
    expect(conns).toHaveLength(1)
    expect(conns[0]).toMatchObject({ target_title: 'pageb', target_id: ids.b, resolved: 1 })

    // Tier context link PageA → Work (target_kind is the tier entity, "area", per RelationTargetKind)
    const link = get(db, 'SELECT * FROM context_links WHERE source_id = ?', ids.a)
    expect(link).toMatchObject({ target_id: ids.work, property_id: '_tier1', target_kind: 'area' })

    // Agenda: the task row + its status property + tier link + schema def
    const task = get(db, 'SELECT * FROM agenda_tasks WHERE id = ?', ids.task)
    expect(task).toMatchObject({ title: 'Buy milk', due_at: '2026-06-20T00:00:00.000Z' })
    expect(JSON.parse(task?.properties as string)._status).toEqual({ $status: 'not_started' })
    const taskLink = get(db, 'SELECT * FROM context_links WHERE source_id = ?', ids.task)
    expect(taskLink).toMatchObject({ source_kind: 'agenda_task', target_id: ids.work })
    // property_definitions mirrors the nexus-wide registry only — agenda config defs stay out (D-1)
    expect(get(db, "SELECT * FROM property_definitions WHERE id = '_status'")).toBeUndefined()

    db.close()
  })

  it('indexes markdown-block [[links]] as block-source edges (D-11)', async () => {
    // A homepage host with one markdown block linking PageB (from the fixture).
    const host = { kind: 'homepage' } as const
    const blockId = '01BLOCKTILE0000000000000A'
    await mkdir(blockHostDir(root, host), { recursive: true })
    await writeFile(blockFilePath(root, host, blockId), 'see [[PageB]]', 'utf8')
    await writeJson(nexusConfig(root, NEXUS_CONFIG_FILES.homepage), {
      blocks: [{ id: blockId, type: 'markdown' }],
    })

    const db = await rebuildIndex(root)
    expect(db).not.toBeNull()
    if (!db) return
    const conns = db
      .prepare('SELECT * FROM connections WHERE source_id = ?')
      .all(blockId) as Record<string, unknown>[]
    expect(conns).toHaveLength(1)
    expect(conns[0]).toMatchObject({
      source_kind: 'block',
      surface: 'block_body',
      target_kind: 'page',
      target_title: 'pageb',
      target_id: ids.b,
      resolved: 1,
    })
    db.close()
  })

  it('falls back to file mtime for an adopted page lacking modified_at (Swift parity)', async () => {
    // A raw `.md` with an id but no timestamps — the adopt-an-Obsidian-vault case.
    // Swift resolves modified_at to the file mtime on load; React must match, not 1970.
    const fixedMtime = new Date('2023-03-04T05:06:07.000Z')
    const adopted = join(root, 'Notes', 'Adopted.md')
    await writeFile(adopted, '---\nid: 01ADOPTEDPAGE\n---\n\nbody\n', 'utf8')
    await utimes(adopted, fixedMtime, fixedMtime)

    const db = await rebuildIndex(root)
    expect(db).not.toBeNull()
    if (!db) return
    const row = get(db, 'SELECT modified_at FROM pages WHERE id = ?', '01ADOPTEDPAGE')
    expect(row?.modified_at).toBe(fixedMtime.toISOString())
    db.close()
  })

  it('keeps the stored modified_at even when file mtime is newer (external edits do not count)', async () => {
    // A stamped page whose file is touched later (e.g. an Obsidian edit) must still
    // report its Pommora-managed stamp, not the mtime — the resolver is stored-wins,
    // never max(stored, mtime). Guards against a future "make external edits count" slip.
    const pageB = join(root, 'Notes', 'PageB.md')
    const future = new Date('2099-01-01T00:00:00.000Z')
    await utimes(pageB, future, future)

    const db = await rebuildIndex(root)
    expect(db).not.toBeNull()
    if (!db) return
    const row = get(db, 'SELECT modified_at FROM pages WHERE id = ?', ids.b)
    expect(row?.modified_at).not.toBe(future.toISOString())
    expect(row?.modified_at).not.toBe('1970-01-01T00:00:00.000Z')
    expect(row?.modified_at as string).toMatch(/^202\d-/) // the real creation-time stamp
    db.close()
  })

  it('reuses the stamped index on a second open (no rebuild)', async () => {
    const first = await rebuildIndex(root)
    first?.close()
    const second = await rebuildIndex(root)
    expect(second).not.toBeNull()
    // Data still present ⇒ it reused rather than wiping + rebuilding empty.
    expect(second && (get(second, 'SELECT COUNT(*) c FROM pages') as { c: number }).c).toBe(3)
    second?.close()
  })
})
