import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { beforeEach, describe, expect, it } from 'vitest'
import { readBlockDoc, writeBlockDoc } from './blocks'

const HOST = { kind: 'homepage' } as const

let root: string
const configPath = (): string => join(root, '.nexus', 'homepage.json')
const readConfig = async (): Promise<Record<string, unknown>> => JSON.parse(await readFile(configPath(), 'utf8'))

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'blocks-'))
  await mkdir(join(root, '.nexus'), { recursive: true })
})

describe('readBlockDoc', () => {
  it('yields an empty doc when the config is missing', async () => {
    expect(await readBlockDoc(root, HOST)).toEqual({ layout: undefined, blocks: [], locked: false })
  })

  it('surfaces layout, blocks, and the lock', async () => {
    await writeFile(
      configPath(),
      JSON.stringify({ banner: 'b.png', layout: { bands: [] }, blocks: [{ id: 'a', type: 'markdown' }], blocks_locked: true })
    )
    const doc = await readBlockDoc(root, HOST)
    expect(doc.layout).toEqual({ bands: [] })
    expect(doc.blocks).toEqual([{ id: 'a', type: 'markdown' }])
    expect(doc.locked).toBe(true)
  })
})

describe('writeBlockDoc', () => {
  it('touches only the patched keys — banner and foreign keys survive', async () => {
    await writeFile(configPath(), JSON.stringify({ banner: 'b.png', swift_future: { x: 1 }, blocks: [] }))
    await writeBlockDoc(root, HOST, { layout: { bands: [] } })
    const cfg = await readConfig()
    expect(cfg.banner).toBe('b.png')
    expect(cfg.swift_future).toEqual({ x: 1 })
    expect(cfg.layout).toEqual({ bands: [] })
    expect(cfg.blocks).toEqual([])
  })

  it('sets and clears the lock key', async () => {
    await writeBlockDoc(root, HOST, { locked: true })
    expect((await readConfig()).blocks_locked).toBe(true)
    await writeBlockDoc(root, HOST, { locked: false })
    expect('blocks_locked' in (await readConfig())).toBe(false)
  })

  it('creates the config from nothing', async () => {
    await writeBlockDoc(root, HOST, { blocks: [{ id: 'a', type: 'markdown' }] })
    expect((await readConfig()).blocks).toEqual([{ id: 'a', type: 'markdown' }])
  })

  it('serializes concurrent writers — no lost update between independent patches', async () => {
    await writeFile(configPath(), JSON.stringify({ banner: 'keep.png' }))
    await Promise.all([
      writeBlockDoc(root, HOST, { layout: { bands: [] } }),
      writeBlockDoc(root, HOST, { locked: true }),
      writeBlockDoc(root, HOST, { blocks: [{ id: 'z', type: 'markdown' }] })
    ])
    const cfg = await readConfig()
    expect(cfg.banner).toBe('keep.png')
    expect(cfg.layout).toEqual({ bands: [] })
    expect(cfg.blocks_locked).toBe(true)
    expect(cfg.blocks).toEqual([{ id: 'z', type: 'markdown' }])
  })
})
