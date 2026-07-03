import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { setOptions, renameOption, removeOption, clearOption } from './optionOps'
import { createProperty } from './registryProperty'
import { assignProperty } from './assignment'
import { createFolderEntity } from './folderEntity'
import { createPage, updatePageProperty } from './page'
import { readRegistry } from '../io/propertiesRegistry'
import type { PropertyDefinition } from '@shared/properties'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-opt-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

async function mkSelect(options: { value: string; label: string; color?: string }[]): Promise<string> {
  const c = await createProperty(root, { id: '', name: 'Tags', type: 'select', select_options: options } as PropertyDefinition)
  if (!c.ok) throw new Error('createProperty failed')
  return c.value.id
}

/** A collection assigning `id`, holding one page whose `id` value is `value`. Returns the page path. */
async function pageHolding(id: string, value: string): Promise<string> {
  const col = await createFolderEntity(root, 'collection', 'Col')
  if (!col.ok) throw new Error('folder failed')
  await assignProperty(root, col.value.path, id)
  const p = await createPage(col.value.path, 'One', { body: 'b' })
  if (!p.ok) throw new Error('page failed')
  await updatePageProperty(p.value.path, id, { kind: 'select', value })
  return p.value.path
}

describe('setOptions', () => {
  it('writes the array verbatim and does NOT re-seed an emptied select', async () => {
    const id = await mkSelect([{ value: 'A', label: 'A' }])
    const r = await setOptions(root, id, [])
    expect(r.ok).toBe(true)
    expect((await readRegistry(root)).defs[id].select_options).toEqual([])
  })

  it('rejects duplicate titles', async () => {
    const id = await mkSelect([{ value: 'A', label: 'A' }])
    const r = await setOptions(root, id, [
      { value: 'A', label: 'A' },
      { value: 'A', label: 'A' }
    ])
    expect(r.ok).toBe(false)
  })

  it('fails for an unknown property id', async () => {
    expect((await setOptions(root, 'prop_nope', [])).ok).toBe(false)
  })
})

describe('option ops reject non-select/multi properties', () => {
  it('all four ops fail on a status property and never corrupt it', async () => {
    const c = await createProperty(root, { id: '', name: 'Stage', type: 'status' } as PropertyDefinition)
    if (!c.ok) throw new Error('createProperty failed')
    const id = c.value.id
    expect((await setOptions(root, id, [{ value: 'X', label: 'X' }])).ok).toBe(false)
    expect((await renameOption(root, id, 'Open', 'Started')).ok).toBe(false)
    expect((await removeOption(root, id, 'Open')).ok).toBe(false)
    expect((await clearOption(root, id, 'Open')).ok).toBe(false)
    const def = (await readRegistry(root)).defs[id]
    expect(def.select_options).toBeUndefined()
    expect(def.status_groups).toHaveLength(3)
  })
})

describe('renameOption', () => {
  it('rewrites the def and cascades the value across pages', async () => {
    const id = await mkSelect([{ value: 'Urgent', label: 'Urgent' }])
    const page = await pageHolding(id, 'Urgent')

    const r = await renameOption(root, id, 'Urgent', 'Critical')
    expect(r.ok).toBe(true)
    expect((await readRegistry(root)).defs[id].select_options).toEqual([{ value: 'Critical', label: 'Critical' }])
    const content = await readFile(page, 'utf8')
    expect(content).toContain('Critical')
    expect(content).not.toContain('Urgent')
  })

  it('rejects a rename that collides with an existing title (no page writes)', async () => {
    const id = await mkSelect([
      { value: 'A', label: 'A' },
      { value: 'B', label: 'B' }
    ])
    const page = await pageHolding(id, 'A')
    const r = await renameOption(root, id, 'A', 'B')
    expect(r.ok).toBe(false)
    expect(await readFile(page, 'utf8')).toContain('A')
  })

  it('fails for an unknown property id', async () => {
    expect((await renameOption(root, 'prop_nope', 'A', 'B')).ok).toBe(false)
  })
})

describe('removeOption', () => {
  it('deletes the def option and strips its value from pages', async () => {
    const id = await mkSelect([
      { value: 'A', label: 'A' },
      { value: 'B', label: 'B' }
    ])
    const page = await pageHolding(id, 'A')

    const r = await removeOption(root, id, 'A')
    expect(r.ok).toBe(true)
    expect((await readRegistry(root)).defs[id].select_options).toEqual([{ value: 'B', label: 'B' }])
    expect(await readFile(page, 'utf8')).not.toContain(id)
  })

  it('fails for an unknown property id', async () => {
    expect((await removeOption(root, 'prop_nope', 'A')).ok).toBe(false)
  })
})

describe('clearOption', () => {
  it('strips the value from pages but KEEPS the option', async () => {
    const id = await mkSelect([{ value: 'A', label: 'A' }])
    const page = await pageHolding(id, 'A')

    const r = await clearOption(root, id, 'A')
    expect(r.ok).toBe(true)
    expect((await readRegistry(root)).defs[id].select_options).toEqual([{ value: 'A', label: 'A' }])
    expect(await readFile(page, 'utf8')).not.toContain(id)
  })

  it('fails for an unknown property id', async () => {
    expect((await clearOption(root, 'prop_nope', 'A')).ok).toBe(false)
  })
})
