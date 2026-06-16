import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, mkdir, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import {
  addProperty,
  renameProperty,
  reorderProperty,
  deleteProperty,
  changePropertyType
} from './schema'
import { createFolderEntity } from './folderEntity'
import { createPage, updatePageProperty } from './page'
import { readSidecar } from '../sidecarIO'
import { pageTypeSidecar } from '@shared/schemas'
import { parseDefinitions } from '../properties/schema'
import { splitFrontmatter } from '../readNexus'
import type { PropertyDefinition } from '@shared/properties'

let root: string
let notes: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-schema-'))
  const c = await createFolderEntity(root, 'pageType', 'Notes')
  if (!c.ok) throw new Error('setup failed')
  notes = c.value.path
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

const defs = async (): Promise<PropertyDefinition[]> =>
  parseDefinitions((await readSidecar(notes, 'pageType', pageTypeSidecar))?.property_definitions)

const def = (over: Partial<PropertyDefinition> & { name: string; type: PropertyDefinition['type'] }) =>
  ({ id: '', ...over }) as PropertyDefinition

describe('addProperty', () => {
  it('mints an id, persists the def, and seeds status groups', async () => {
    const r = await addProperty(notes, def({ name: 'Score', type: 'number' }))
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.value.id.startsWith('prop_')).toBe(true)

    const s = await addProperty(notes, def({ name: 'Stage', type: 'status' }))
    expect(s.ok).toBe(true)
    const all = await defs()
    expect(all.map((d) => d.name)).toEqual(['Score', 'Stage'])
    const stage = all.find((d) => d.name === 'Stage')!
    expect(stage.status_groups?.map((g) => g.id)).toEqual(['upcoming', 'in_progress', 'done'])
  })

  it('rejects reserved ids and duplicate names', async () => {
    await addProperty(notes, def({ name: 'Score', type: 'number' }))
    expect((await addProperty(notes, { id: '_status', name: 'X', type: 'number' } as PropertyDefinition)).ok).toBe(false)
    expect((await addProperty(notes, def({ name: 'score', type: 'number' }))).ok).toBe(false) // case-insensitive dup
  })
})

describe('renameProperty', () => {
  it('renames by id and rejects unknown id + duplicate name', async () => {
    const a = await addProperty(notes, def({ name: 'Score', type: 'number' }))
    await addProperty(notes, def({ name: 'Stage', type: 'status' }))
    if (!a.ok) return
    expect((await renameProperty(notes, a.value.id, 'Points')).ok).toBe(true)
    expect((await defs()).find((d) => d.id === a.value.id)?.name).toBe('Points')
    expect((await renameProperty(notes, 'nope', 'X')).ok).toBe(false)
    expect((await renameProperty(notes, a.value.id, 'Stage')).ok).toBe(false)
  })
})

describe('reorderProperty', () => {
  it('moves a property to a new index', async () => {
    await addProperty(notes, def({ name: 'A', type: 'number' }))
    const b = await addProperty(notes, def({ name: 'B', type: 'number' }))
    await addProperty(notes, def({ name: 'C', type: 'number' }))
    if (!b.ok) return
    expect((await reorderProperty(notes, b.value.id, 0)).ok).toBe(true)
    expect((await defs()).map((d) => d.name)).toEqual(['B', 'A', 'C'])
  })
})

describe('deleteProperty', () => {
  it('removes the def and strips the value from every member page (incl. nested)', async () => {
    const p = await addProperty(notes, def({ name: 'Score', type: 'number' }))
    if (!p.ok) return
    const id = p.value.id

    const top = await createPage(notes, 'Top', { body: 'b' })
    const sub = join(notes, 'Collection')
    await mkdir(sub, { recursive: true })
    const nested = await createPage(sub, 'Nested', { body: 'b' })
    if (!top.ok || !nested.ok) return
    await updatePageProperty(top.value.path, id, { kind: 'number', value: 5 })
    await updatePageProperty(nested.value.path, id, { kind: 'number', value: 9 })

    expect((await deleteProperty(notes, id)).ok).toBe(true)

    expect((await defs()).some((d) => d.id === id)).toBe(false)
    for (const path of [top.value.path, nested.value.path]) {
      const fm = splitFrontmatter(await readFile(path, 'utf8'))
      expect((fm.properties as Record<string, unknown>)[id]).toBeUndefined()
      expect(fm.id).toBeTruthy() // other frontmatter preserved
    }
  })

  it('fails for an unknown property id', async () => {
    expect((await deleteProperty(notes, 'nope')).ok).toBe(false)
  })
})

describe('changePropertyType', () => {
  it('lossless same-type change is a sidecar-only bump', async () => {
    const p = await addProperty(notes, def({ name: 'Score', type: 'number' }))
    if (!p.ok) return
    expect((await changePropertyType(notes, p.value.id, 'number')).ok).toBe(true)
    expect((await defs()).find((d) => d.id === p.value.id)?.type).toBe('number')
  })

  it('lossy change requires confirmation, then strips member values', async () => {
    const p = await addProperty(notes, def({ name: 'Score', type: 'number' }))
    if (!p.ok) return
    const id = p.value.id
    const page = await createPage(notes, 'P', { body: 'b' })
    if (!page.ok) return
    await updatePageProperty(page.value.path, id, { kind: 'number', value: 5 })

    const blocked = await changePropertyType(notes, id, 'url')
    expect(blocked.ok).toBe(false)
    if (!blocked.ok) expect(blocked.error.code).toBe('lossy-change-requires-confirmation')

    expect((await changePropertyType(notes, id, 'url', { dropConflictingValues: true })).ok).toBe(true)
    expect((await defs()).find((d) => d.id === id)?.type).toBe('url')
    const fm = splitFrontmatter(await readFile(page.value.path, 'utf8'))
    expect((fm.properties as Record<string, unknown>)[id]).toBeUndefined()
  })
})
