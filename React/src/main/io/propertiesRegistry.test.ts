import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, writeFile, mkdir } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { readRegistry, writeRegistry } from './propertiesRegistry'
import type { PropertyDefinition } from '@shared/properties'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-registry-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

const def = (id: string, name: string): PropertyDefinition =>
  ({ id, name, type: 'select', select_options: [{ value: 'a', label: 'A', color: 'blue' }] }) as PropertyDefinition

describe('propertiesRegistry', () => {
  it('reads empty when the file is absent', async () => {
    expect(await readRegistry(root)).toEqual({ order: [], defs: {} })
  })

  it('round-trips a written registry file', async () => {
    const reg = { order: ['prop_b', 'prop_a'], defs: { prop_a: def('prop_a', 'Priority'), prop_b: def('prop_b', 'Status') } }
    await writeRegistry(root, reg)
    expect(await readRegistry(root)).toEqual(reg)
  })

  it('drops entries that fail the def schema, keeps valid ones', async () => {
    await mkdir(join(root, '.nexus'), { recursive: true })
    await writeFile(
      join(root, '.nexus', 'properties.json'),
      JSON.stringify({ prop_a: def('prop_a', 'Priority'), prop_bad: { id: 'prop_bad' } })
    )
    expect(Object.keys((await readRegistry(root)).defs)).toEqual(['prop_a'])
  })
})

describe('RegistryFile shape — { order, defs } with legacy migration', () => {
  it('reads a legacy bare-Record file as { order: [], defs }', async () => {
    await mkdir(join(root, '.nexus'), { recursive: true })
    await writeFile(
      join(root, '.nexus', 'properties.json'),
      JSON.stringify({ prop_a: def('prop_a', 'Priority') })
    )
    const reg = await readRegistry(root)
    expect(reg.defs.prop_a?.id).toBe('prop_a')
    expect(reg.order).toEqual([])
  })

  it('element-filters junk order entries — non-strings and ids without defs dropped (B-3)', async () => {
    await mkdir(join(root, '.nexus'), { recursive: true })
    await writeFile(
      join(root, '.nexus', 'properties.json'),
      JSON.stringify({ order: ['prop_a', 42, null, 'prop_gone'], defs: { prop_a: def('prop_a', 'Priority') } })
    )
    expect((await readRegistry(root)).order).toEqual(['prop_a'])
  })
})
