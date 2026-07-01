import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { createProperty, editProperty, removeFromRegistry } from './registryProperty'
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
    expect(reg[r.value.id].status_groups?.map((g) => g.id)).toEqual(['upcoming', 'in_progress', 'done'])
  })

  it('rejects a name that clashes anywhere in the registry (case-insensitive)', async () => {
    await createProperty(root, def({ name: 'Priority', type: 'select' }))
    expect((await createProperty(root, def({ name: 'priority', type: 'number' }))).ok).toBe(false)
  })

  it('serializes overlapping mutations — no lost update on the shared registry file', async () => {
    const results = await Promise.all([
      createProperty(root, def({ name: 'One', type: 'number' })),
      createProperty(root, def({ name: 'Two', type: 'number' })),
      createProperty(root, def({ name: 'Three', type: 'number' }))
    ])
    expect(results.every((r) => r.ok)).toBe(true)
    const reg = await readRegistry(root)
    expect(Object.values(reg).map((d) => d.name).sort()).toEqual(['One', 'Three', 'Two'])
  })
})

describe('editProperty', () => {
  it('renames in place, keeping the id', async () => {
    const c = await createProperty(root, def({ name: 'Old', type: 'number' }))
    if (!c.ok) return
    expect((await editProperty(root, c.value.id, { name: 'New' })).ok).toBe(true)
    expect((await readRegistry(root))[c.value.id].name).toBe('New')
  })

  it('rejects renaming onto another def', async () => {
    await createProperty(root, def({ name: 'Alpha', type: 'number' }))
    const b = await createProperty(root, def({ name: 'Beta', type: 'number' }))
    if (!b.ok) return
    expect((await editProperty(root, b.value.id, { name: 'Alpha' })).ok).toBe(false)
  })
})

describe('removeFromRegistry', () => {
  it('drops the def', async () => {
    const c = await createProperty(root, def({ name: 'Temp', type: 'number' }))
    if (!c.ok) return
    expect((await removeFromRegistry(root, c.value.id)).ok).toBe(true)
    expect(await readRegistry(root)).toEqual({})
  })
})
