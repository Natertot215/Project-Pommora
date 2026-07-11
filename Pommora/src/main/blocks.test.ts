import { mkdir, mkdtemp, readFile, readdir, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { beforeEach, describe, expect, it } from 'vitest'
import { pathExists } from './io/atomicWrite'
import {
  blockFilePath,
  convertTileToView,
  duplicateBlockTile,
  createMarkdownBlock,
  readBlockDoc,
  readMarkdownBlock,
  removeBlockTile,
  writeBlockDoc,
  writeMarkdownBlock
} from './blocks'

const HOST = { kind: 'homepage' } as const

let root: string
const configPath = (): string => join(root, '.nexus', 'homepage.json')
const sidecarPath = (): string => join(root, '.nexus', 'homepage', '_blocks.json')
const readConfig = async (): Promise<Record<string, unknown>> => JSON.parse(await readFile(configPath(), 'utf8'))

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'blocks-'))
  await mkdir(join(root, '.nexus', 'homepage'), { recursive: true })
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

  it('heals the interim split-doc sidecar back onto the host config', async () => {
    await writeFile(configPath(), JSON.stringify({ banner: 'b.png' }))
    await writeFile(
      sidecarPath(),
      JSON.stringify({ layout: { bands: [] }, blocks: [{ id: 'a', type: 'markdown' }], blocks_locked: true })
    )
    const doc = await readBlockDoc(root, HOST)
    expect(doc.layout).toEqual({ bands: [] })
    expect(doc.blocks).toEqual([{ id: 'a', type: 'markdown' }])
    expect(doc.locked).toBe(true)
    const cfg = await readConfig()
    expect(cfg.banner).toBe('b.png')
    expect(cfg.blocks).toEqual([{ id: 'a', type: 'markdown' }])
    expect(await pathExists(sidecarPath())).toBe(false)
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

describe('markdown block lifecycle', () => {
  it('create mints the dir + empty file + entry; the body round-trips pure (no frontmatter)', async () => {
    const id = await createMarkdownBlock(root, HOST)
    expect(await pathExists(blockFilePath(root, HOST, id))).toBe(true)
    expect((await readConfig()).blocks).toEqual([{ id, type: 'markdown' }])

    await writeMarkdownBlock(root, HOST, id, '# Hi\n\n[[Some Page]]\n')
    expect(await readMarkdownBlock(root, HOST, id)).toBe('# Hi\n\n[[Some Page]]\n')
    expect(await readFile(blockFilePath(root, HOST, id), 'utf8')).not.toContain('---')
  })

  it('remove drops the entry and trashes the file; foreign entries survive', async () => {
    await writeBlockDoc(root, HOST, { blocks: [{ id: 'alien', type: 'widget', keep: true }] })
    const id = await createMarkdownBlock(root, HOST)
    await removeBlockTile(root, HOST, id)
    expect((await readConfig()).blocks).toEqual([{ id: 'alien', type: 'widget', keep: true }])
    expect(await pathExists(blockFilePath(root, HOST, id))).toBe(false)
    const trashed = await readdir(join(root, '.trash'))
    expect(trashed.some((f) => f.includes(id))).toBe(true)
  })

  it('convert to view stamps a payload-local config id and trashes the markdown file', async () => {
    const id = await createMarkdownBlock(root, HOST)
    await writeBlockDoc(root, HOST, {
      blocks: [{ id, type: 'markdown', style: 'borderless', swift_key: 1 }]
    })
    await convertTileToView(root, HOST, id, [
      { source_id: 'src1', config: { id: 'source-view-id', name: 'Table', foreign: true } }
    ])
    const blocks = (await readConfig()).blocks as Array<Record<string, unknown>>
    const entry = blocks[0]
    expect(entry.type).toBe('view')
    expect(entry.style).toBe('borderless')
    expect(entry.swift_key).toBe(1)
    expect(entry.active).toBe(0)
    const view = (entry.views as Array<Record<string, unknown>>)[0]
    expect(view.source_id).toBe('src1')
    const config = view.config as Record<string, unknown>
    expect(config.name).toBe('Table')
    expect(config.foreign).toBe(true)
    expect(config.id).not.toBe('source-view-id')
    expect(typeof config.id).toBe('string')
    expect(await pathExists(blockFilePath(root, HOST, id))).toBe(false)
    const trashed = await readdir(join(root, '.trash'))
    expect(trashed.some((f) => f.includes(id))).toBe(true)
  })

  it('duplicate copies the raw entry + file; a view copy re-mints its config ids', async () => {
    const id = await createMarkdownBlock(root, HOST)
    await writeMarkdownBlock(root, HOST, id, 'body text')
    await writeBlockDoc(root, HOST, { blocks: [{ id, type: 'markdown', style: 'borderless', alien: 1 }] })
    const dupId = await duplicateBlockTile(root, HOST, id)
    expect(dupId).toBeTruthy()
    expect(await readMarkdownBlock(root, HOST, dupId as string)).toBe('body text')
    const blocks = (await readConfig()).blocks as Array<Record<string, unknown>>
    const copy = blocks.find((b) => b.id === dupId)
    expect(copy).toMatchObject({ type: 'markdown', style: 'borderless', alien: 1 })

    await writeBlockDoc(root, HOST, {
      blocks: [{ id: 'v1', type: 'view', views: [{ source_id: 's', config: { id: 'cfg-a', name: 'T' } }] }]
    })
    const dupView = await duplicateBlockTile(root, HOST, 'v1')
    const after = (await readConfig()).blocks as Array<Record<string, unknown>>
    const viewCopy = after.find((b) => b.id === dupView) as { views: Array<{ config: { id: string } }> }
    expect(viewCopy.views[0].config.id).not.toBe('cfg-a')
    expect((after.find((b) => b.id === 'v1') as { views: Array<{ config: { id: string } }> }).views[0].config.id).toBe('cfg-a')
  })

  it('removing a non-markdown tile touches no files', async () => {
    await writeBlockDoc(root, HOST, { blocks: [{ id: 'p1', type: 'page', page_id: 'x' }] })
    await removeBlockTile(root, HOST, 'p1')
    expect((await readConfig()).blocks).toEqual([])
    expect(await pathExists(join(root, '.trash'))).toBe(false)
  })
})
