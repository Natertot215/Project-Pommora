import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, readFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { createProperty, editProperty, removeFromRegistry, reorderRegistry } from './registryProperty'
import { readRegistry } from '../io/propertiesRegistry'
import type { PropertyDefinition } from '@shared/properties'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-regcrud-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

const def = (over: Partial<PropertyDefinition> & { name: string; type: PropertyDefinition['type'] }) =>
  ({ id: '', ...over }) as PropertyDefinition

describe('createProperty', () => {
  it('mints a prop_ id, seeds status groups, and persists to the registry', async () => {
    const r = await createProperty(root, def({ name: 'Stage', type: 'status' }))
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.value.id.startsWith('prop_')).toBe(true)
    const reg = await readRegistry(root)
    expect(reg.defs[r.value.id].status_groups?.map((g) => g.id)).toEqual(['upcoming', 'in_progress', 'done'])
  })

  it('allows duplicate names on create — the flat D-3 policy (ids keep twins mechanically safe)', async () => {
    await createProperty(root, def({ name: 'Priority', type: 'select' }))
    expect((await createProperty(root, def({ name: 'priority', type: 'number' }))).ok).toBe(true)
  })

  it('a blank name still rejects', async () => {
    expect((await createProperty(root, def({ name: '  ', type: 'number' }))).ok).toBe(false)
  })

  it('appends each new id to the nexus order (A-9)', async () => {
    const a = await createProperty(root, def({ name: 'One', type: 'number' }))
    const b = await createProperty(root, def({ name: 'Two', type: 'number' }))
    if (!a.ok || !b.ok) throw new Error('create failed')
    expect((await readRegistry(root)).order).toEqual([a.value.id, b.value.id])
  })

  it('serializes overlapping mutations — no lost update on the shared registry file', async () => {
    const results = await Promise.all([
      createProperty(root, def({ name: 'One', type: 'number' })),
      createProperty(root, def({ name: 'Two', type: 'number' })),
      createProperty(root, def({ name: 'Three', type: 'number' }))
    ])
    expect(results.every((r) => r.ok)).toBe(true)
    const reg = await readRegistry(root)
    expect(Object.values(reg.defs).map((d) => d.name).sort()).toEqual(['One', 'Three', 'Two'])
  })
})

describe('editProperty', () => {
  it('renames in place, keeping the id', async () => {
    const c = await createProperty(root, def({ name: 'Old', type: 'number' }))
    if (!c.ok) return
    expect((await editProperty(root, c.value.id, { name: 'New' })).ok).toBe(true)
    expect((await readRegistry(root)).defs[c.value.id].name).toBe('New')
  })

  it('allows renaming onto another def name — the flat D-3 policy on BOTH write paths', async () => {
    await createProperty(root, def({ name: 'Alpha', type: 'number' }))
    const b = await createProperty(root, def({ name: 'Beta', type: 'number' }))
    if (!b.ok) return
    expect((await editProperty(root, b.value.id, { name: 'Alpha' })).ok).toBe(true)
  })

  it('writes and then clears a checkbox property color in place', async () => {
    const c = await createProperty(root, def({ name: 'Done', type: 'checkbox' }))
    if (!c.ok) return
    await editProperty(root, c.value.id, { checkbox_color: 'blue' })
    expect((await readRegistry(root)).defs[c.value.id].checkbox_color).toBe('blue')
    await editProperty(root, c.value.id, { checkbox_color: undefined })
    expect((await readRegistry(root)).defs[c.value.id].checkbox_color).toBeUndefined()
  })
})

describe('removeFromRegistry', () => {
  it('drops the def AND its order entry — no dangling id on disk', async () => {
    const c = await createProperty(root, def({ name: 'Temp', type: 'number' }))
    if (!c.ok) return
    expect((await removeFromRegistry(root, c.value.id)).ok).toBe(true)
    expect(await readRegistry(root)).toEqual({ order: [], defs: {} })
    const raw = JSON.parse(await readFile(join(root, '.nexus', 'properties.json'), 'utf8'))
    expect(raw.order).toEqual([]) // the write-side filter, not the lenient read, cleans it
  })
})

describe('reorderRegistry', () => {
  it('moves an id within the nexus order (C-1)', async () => {
    const ids: string[] = []
    for (const name of ['One', 'Two', 'Three']) {
      const r = await createProperty(root, def({ name, type: 'number' }))
      if (r.ok) ids.push(r.value.id)
    }
    expect((await reorderRegistry(root, ids[2], 0)).ok).toBe(true)
    expect((await readRegistry(root)).order).toEqual([ids[2], ids[0], ids[1]])
  })

  it('clamps an out-of-range index and rejects an unknown id', async () => {
    const a = await createProperty(root, def({ name: 'Only', type: 'number' }))
    if (!a.ok) return
    expect((await reorderRegistry(root, a.value.id, 99)).ok).toBe(true)
    expect((await reorderRegistry(root, 'prop_ghost', 0)).ok).toBe(false)
  })
})
