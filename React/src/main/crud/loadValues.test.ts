import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, mkdir, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { loadValues } from './loadValues'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-loadvalues-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

describe('loadValues', () => {
  it('maps page id → frontmatter across the container and its nested Sets', async () => {
    await mkdir(join(root, 'Col', 'SetA'), { recursive: true })
    await writeFile(
      join(root, 'Col', 'p1.md'),
      '---\nid: p1\ntier1:\n  - area1\nproperties:\n  prop_status:\n    $status: in_progress\n---\n\nbody\n'
    )
    await writeFile(
      join(root, 'Col', 'SetA', 'p2.md'),
      '---\nid: p2\nproperties:\n  prop_num: 7\n---\n\nbody\n'
    )

    const values = await loadValues(root, 'Col')
    expect(Object.keys(values).sort()).toEqual(['p1', 'p2'])
    expect(values.p1.tier1).toEqual(['area1'])
    expect(values.p1.properties?.prop_status).toEqual({ $status: 'in_progress' })
    expect(values.p2.properties?.prop_num).toBe(7)
  })

  it('keys an id-less page by its adopted id', async () => {
    await mkdir(join(root, 'Col'), { recursive: true })
    await writeFile(join(root, 'Col', 'noid.md'), '---\ntitle: x\n---\n\nbody\n')

    const values = await loadValues(root, 'Col')
    const keys = Object.keys(values)
    expect(keys).toHaveLength(1)
    expect(keys[0]).toMatch(/^adopted-/)
  })

  it('returns an empty map for an absent container', async () => {
    expect(await loadValues(root, 'Nope')).toEqual({})
  })
})
