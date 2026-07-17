import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import {
  setOptions,
  renameOption,
  removeOption,
  clearOption,
  renameStatusOption,
  removeStatusOption,
  clearStatusOption,
} from './optionOps'
import { createProperty, editProperty } from './registryProperty'
import { assignProperty } from './assignment'
import { createFolderEntity } from './folderEntity'
import { createPage, updatePageProperty } from './page'
import { serializeSchemaOp } from './schemaChain'
import { readRegistry } from '../io/propertiesRegistry'
import type { PropertyDefinition } from '@shared/properties'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-opt-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

async function mkSelect(
  options: { value: string; label: string; color?: string }[],
): Promise<string> {
  const c = await createProperty(root, {
    id: '',
    name: 'Tags',
    type: 'select',
    select_options: options,
  } as PropertyDefinition)
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

/** A Status property seeded Open / Active / Done (upcoming / in_progress / done groups). */
async function mkStatus(): Promise<string> {
  const c = await createProperty(root, {
    id: '',
    name: 'Stage',
    type: 'status',
  } as PropertyDefinition)
  if (!c.ok) throw new Error('createProperty failed')
  return c.value.id
}

/** A collection assigning the Status property `id`, holding one page whose `$status` is `value`. */
async function statusPageHolding(id: string, value: string): Promise<string> {
  const col = await createFolderEntity(root, 'collection', 'Col')
  if (!col.ok) throw new Error('folder failed')
  await assignProperty(root, col.value.path, id)
  const p = await createPage(col.value.path, 'One', { body: 'b' })
  if (!p.ok) throw new Error('page failed')
  await updatePageProperty(p.value.path, id, { kind: 'status', value })
  return p.value.path
}

/** Every option value across a property's status groups, flattened. */
async function statusValues(id: string): Promise<string[]> {
  const def = (await readRegistry(root)).defs[id]
  return (def.status_groups ?? []).flatMap((g) => g.options.map((o) => o.value))
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
      { value: 'A', label: 'A' },
    ])
    expect(r.ok).toBe(false)
  })

  it('fails for an unknown property id', async () => {
    expect((await setOptions(root, 'prop_nope', [])).ok).toBe(false)
  })

  it('an emptied options list survives an unrelated property edit — no phantom re-seed (F2)', async () => {
    const id = await mkSelect([{ value: 'A', label: 'A' }])
    await setOptions(root, id, [])
    await editProperty(root, id, { name: 'Renamed Tags' })
    expect((await readRegistry(root)).defs[id].select_options).toEqual([])
  })

  it('serializes on the schema chain — queues behind an in-flight schema op, never interleaving', async () => {
    const id = await mkSelect([{ value: 'A', label: 'A' }])
    const order: string[] = []
    let release!: () => void
    const gate = new Promise<void>((r) => {
      release = r
    })
    // Occupy the shared schema chain with a gated op, THEN fire setOptions. If setOptions rode a
    // different lock it would slip past the gate and land first (the cross-chain race, finding #3).
    const slow = serializeSchemaOp(async () => {
      await gate
      order.push('schema-op')
    })
    const fast = setOptions(root, id, [{ value: 'B', label: 'B' }]).then(() =>
      order.push('setOptions'),
    )
    await new Promise((r) => setTimeout(r, 50))
    release()
    await Promise.all([slow, fast])
    expect(order).toEqual(['schema-op', 'setOptions'])
  })
})

describe('option ops reject non-select/multi properties', () => {
  it('all four ops fail on a status property and never corrupt it', async () => {
    const c = await createProperty(root, {
      id: '',
      name: 'Stage',
      type: 'status',
    } as PropertyDefinition)
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
    expect((await readRegistry(root)).defs[id].select_options).toEqual([
      { value: 'Critical', label: 'Critical' },
    ])
    const content = await readFile(page, 'utf8')
    expect(content).toContain('Critical')
    expect(content).not.toContain('Urgent')
  })

  it('rejects a rename that collides with an existing title (no page writes)', async () => {
    const id = await mkSelect([
      { value: 'A', label: 'A' },
      { value: 'B', label: 'B' },
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
      { value: 'B', label: 'B' },
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

describe('status ops reject non-status properties', () => {
  it('all three fail on a select property and never corrupt it', async () => {
    const id = await mkSelect([{ value: 'A', label: 'A' }])
    expect((await renameStatusOption(root, id, 'A', 'B')).ok).toBe(false)
    expect((await removeStatusOption(root, id, 'A')).ok).toBe(false)
    expect((await clearStatusOption(root, id, 'A')).ok).toBe(false)
    expect((await readRegistry(root)).defs[id].select_options).toEqual([{ value: 'A', label: 'A' }])
  })
})

describe('renameStatusOption', () => {
  it('rewrites the group option and cascades the value onto $status pages', async () => {
    const id = await mkStatus()
    const page = await statusPageHolding(id, 'Open')

    const r = await renameStatusOption(root, id, 'Open', 'Started')
    expect(r.ok).toBe(true)
    expect(await statusValues(id)).toContain('Started')
    expect(await statusValues(id)).not.toContain('Open')
    const content = await readFile(page, 'utf8')
    expect(content).toContain('Started')
    expect(content).not.toContain('Open')
  })

  it('rejects a rename colliding with another option value property-wide (no page writes)', async () => {
    const id = await mkStatus()
    const page = await statusPageHolding(id, 'Open')
    const r = await renameStatusOption(root, id, 'Open', 'Active') // 'Active' already lives in another group
    expect(r.ok).toBe(false)
    expect(await readFile(page, 'utf8')).toContain('Open')
  })

  it('fails for an unknown property id', async () => {
    expect((await renameStatusOption(root, 'prop_nope', 'A', 'B')).ok).toBe(false)
  })
})

describe('removeStatusOption', () => {
  it('drops the option from its group and strips its value from pages', async () => {
    const id = await mkStatus()
    const page = await statusPageHolding(id, 'Active')

    const r = await removeStatusOption(root, id, 'Active')
    expect(r.ok).toBe(true)
    expect(await statusValues(id)).not.toContain('Active')
    expect(await readFile(page, 'utf8')).not.toContain(id)
  })
})

describe('clearStatusOption', () => {
  it('strips the value from pages but KEEPS the option in its group', async () => {
    const id = await mkStatus()
    const page = await statusPageHolding(id, 'Done')

    const r = await clearStatusOption(root, id, 'Done')
    expect(r.ok).toBe(true)
    expect(await statusValues(id)).toContain('Done')
    expect(await readFile(page, 'utf8')).not.toContain(id)
  })
})
