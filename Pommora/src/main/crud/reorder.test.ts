import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile, mkdir } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { setStateOrder, setContainerOrder, setChildOrder } from './reorder'
import { createFolderEntity } from './folderEntity'
import { readSidecar } from '../sidecarIO'
import { pageCollectionSidecar, pageSetSidecar } from '@shared/schemas'
import { nexusConfig, NEXUS_CONFIG_FILES } from '../paths'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-reorder-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

async function readState(): Promise<Record<string, unknown>> {
  return JSON.parse(await readFile(nexusConfig(root, NEXUS_CONFIG_FILES.state), 'utf8'))
}

describe('setStateOrder', () => {
  it('persists a top-level order to .nexus/state.json (creating .nexus)', async () => {
    await setStateOrder(root, 'collection_order', ['b', 'a', 'c'])
    expect((await readState()).collection_order).toEqual(['b', 'a', 'c'])
  })

  it('does not clobber other state keys (read-modify-write)', async () => {
    await setStateOrder(root, 'collection_order', ['a'])
    await setStateOrder(root, 'area_order', ['x', 'y'])
    const state = await readState()
    expect(state.collection_order).toEqual(['a'])
    expect(state.area_order).toEqual(['x', 'y'])
  })

  it('never persists adopted- placeholder ids', async () => {
    await setStateOrder(root, 'collection_order', ['01ABC', 'adopted-deadbeef', '01XYZ'])
    expect((await readState()).collection_order).toEqual(['01ABC', '01XYZ'])
  })
})

describe('setContainerOrder', () => {
  it('persists page_order to a container sidecar, preserving other keys', async () => {
    const c = await createFolderEntity(root, 'collection', 'Notes', { icon: 'box' })
    if (!c.ok) throw new Error('setup failed')
    const r = await setContainerOrder(
      c.value.path,
      'collection',
      pageCollectionSidecar,
      'page_order',
      ['p2', 'p1'],
    )
    expect(r.ok).toBe(true)
    expect(await readSidecar(c.value.path, 'collection', pageCollectionSidecar)).toMatchObject({
      id: c.value.id,
      icon: 'box',
      page_order: ['p2', 'p1'],
    })
  })
})

describe('setChildOrder', () => {
  it('detects the folder kind from its sidecar and writes page_order (a set)', async () => {
    const s = await createFolderEntity(root, 'set', 'Reading')
    if (!s.ok) throw new Error('setup failed')
    const r = await setChildOrder(s.value.path, 'page_order', ['p3', 'p1', 'p2'])
    expect(r.ok).toBe(true)
    expect(await readSidecar(s.value.path, 'set', pageSetSidecar)).toMatchObject({
      page_order: ['p3', 'p1', 'p2'],
    })
  })

  it('writes set_order to a collection sidecar', async () => {
    const c = await createFolderEntity(root, 'collection', 'Notes', { icon: 'box' })
    if (!c.ok) throw new Error('setup failed')
    const r = await setChildOrder(c.value.path, 'set_order', ['s2', 's1'])
    expect(r.ok).toBe(true)
    expect(await readSidecar(c.value.path, 'collection', pageCollectionSidecar)).toMatchObject({
      set_order: ['s2', 's1'],
    })
  })

  it('is a tolerated no-op for a folder with no recognized sidecar', async () => {
    const raw = join(root, 'Raw')
    await mkdir(raw, { recursive: true })
    expect((await setChildOrder(raw, 'page_order', ['p1'])).ok).toBe(true)
  })

  it('strips adopted- placeholder ids before writing', async () => {
    const c = await createFolderEntity(root, 'collection', 'Notes')
    if (!c.ok) throw new Error('setup failed')
    await setChildOrder(c.value.path, 'set_order', ['s1', 'adopted-cafe', 's2'])
    expect(await readSidecar(c.value.path, 'collection', pageCollectionSidecar)).toMatchObject({
      set_order: ['s1', 's2'],
    })
  })
})
