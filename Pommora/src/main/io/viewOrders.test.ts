import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile, writeFile, mkdir } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { readViewOrders, writeViewOrders } from './viewOrders'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-vieworders-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

describe('per-machine view-order cache (.nexus/viewOrders.json)', () => {
  it('reads empty when the file is absent', async () => {
    expect(await readViewOrders(root)).toEqual({})
  })

  it('round-trips a manual order keyed by view id', async () => {
    await writeViewOrders(root, 'view_a', ['p1', 'p2', 'p3'])
    expect((await readViewOrders(root))['view_a']).toEqual(['p1', 'p2', 'p3'])
  })

  it('writes to .nexus/viewOrders.json (per-machine, out of the synced sidecar)', async () => {
    await writeViewOrders(root, 'view_a', ['p1'])
    const raw = await readFile(join(root, '.nexus', 'viewOrders.json'), 'utf8')
    expect(JSON.parse(raw)['view_a']).toEqual(['p1'])
  })

  it('clears a view entry when written with an empty array', async () => {
    await writeViewOrders(root, 'view_a', ['p1'])
    await writeViewOrders(root, 'view_a', [])
    expect(await readViewOrders(root)).toEqual({})
  })

  it('keeps other views intact when one changes', async () => {
    await writeViewOrders(root, 'view_a', ['p1'])
    await writeViewOrders(root, 'view_b', ['p2'])
    await writeViewOrders(root, 'view_a', ['p3'])
    const all = await readViewOrders(root)
    expect(all['view_a']).toEqual(['p3'])
    expect(all['view_b']).toEqual(['p2'])
  })

  it('drops non-string members on read (lenient)', async () => {
    await mkdir(join(root, '.nexus'), { recursive: true })
    await writeFile(
      join(root, '.nexus', 'viewOrders.json'),
      JSON.stringify({ view_a: ['p1', 2, null, 'p2'] }),
    )
    expect((await readViewOrders(root))['view_a']).toEqual(['p1', 'p2'])
  })

  it('serializes overlapping writes so none is lost (no read-merge-write race)', async () => {
    await Promise.all(
      Array.from({ length: 20 }, (_, i) => writeViewOrders(root, `view_${i}`, [`p${i}`])),
    )
    const all = await readViewOrders(root)
    for (let i = 0; i < 20; i++) expect(all[`view_${i}`]).toEqual([`p${i}`])
  })
})
