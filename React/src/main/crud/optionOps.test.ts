import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { setOptions } from './optionOps'
import { createProperty } from './registryProperty'
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
