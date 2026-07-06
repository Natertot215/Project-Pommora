import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { readActiveViews, writeActiveViews } from './activeViews'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-activeviews-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

describe('active-view pointer (.nexus/activeViews.json)', () => {
  it('reads empty when the file is absent', async () => {
    expect(await readActiveViews(root)).toEqual({})
  })

  it('round-trips the active view id keyed by container id', async () => {
    await writeActiveViews(root, 'col-1', 'view_abc')
    expect((await readActiveViews(root))['col-1']).toBe('view_abc')
  })

  it('writes to .nexus/activeViews.json (per-machine, out of the synced sidecar)', async () => {
    await writeActiveViews(root, 'col-1', 'view_abc')
    const raw = await readFile(join(root, '.nexus', 'activeViews.json'), 'utf8')
    expect(JSON.parse(raw)['col-1']).toBe('view_abc')
  })

  it('clears a container entry when written with an empty view id', async () => {
    await writeActiveViews(root, 'col-1', 'view_abc')
    await writeActiveViews(root, 'col-1', '')
    expect(await readActiveViews(root)).toEqual({})
  })

  it('keeps other containers intact when one changes', async () => {
    await writeActiveViews(root, 'col-1', 'view_a')
    await writeActiveViews(root, 'col-2', 'view_b')
    await writeActiveViews(root, 'col-1', 'view_c')
    const state = await readActiveViews(root)
    expect(state['col-1']).toBe('view_c')
    expect(state['col-2']).toBe('view_b')
  })

  it('serializes overlapping writes so none is lost (no read-merge-write race)', async () => {
    await Promise.all(
      Array.from({ length: 20 }, (_, i) => writeActiveViews(root, `col-${i}`, `view_${i}`))
    )
    const state = await readActiveViews(root)
    for (let i = 0; i < 20; i++) expect(state[`col-${i}`]).toBe(`view_${i}`)
  })
})
