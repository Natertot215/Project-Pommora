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
  it('reads {} when the file is absent', async () => {
    expect(await readRegistry(root)).toEqual({})
  })

  it('round-trips a written registry', async () => {
    const reg = { prop_a: def('prop_a', 'Priority'), prop_b: def('prop_b', 'Status') }
    await writeRegistry(root, reg)
    expect(await readRegistry(root)).toEqual(reg)
  })

  it('drops entries that fail the def schema, keeps valid ones', async () => {
    await mkdir(join(root, '.nexus'), { recursive: true })
    await writeFile(
      join(root, '.nexus', 'properties.json'),
      JSON.stringify({ prop_a: def('prop_a', 'Priority'), prop_bad: { id: 'prop_bad' } })
    )
    expect(Object.keys(await readRegistry(root))).toEqual(['prop_a'])
  })
})
