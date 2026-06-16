import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { setStateOrder, setContainerOrder } from './reorder'
import { createFolderEntity } from './folderEntity'
import { readSidecar } from '../sidecarIO'
import { pageTypeSidecar } from '@shared/schemas'
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
    await setStateOrder(root, 'vault_order', ['b', 'a', 'c'])
    expect((await readState()).vault_order).toEqual(['b', 'a', 'c'])
  })

  it('does not clobber other state keys (read-modify-write)', async () => {
    await setStateOrder(root, 'vault_order', ['a'])
    await setStateOrder(root, 'area_order', ['x', 'y'])
    const state = await readState()
    expect(state.vault_order).toEqual(['a'])
    expect(state.area_order).toEqual(['x', 'y'])
  })
})

describe('setContainerOrder', () => {
  it('persists page_order to a container sidecar, preserving other keys', async () => {
    const c = await createFolderEntity(root, 'pageType', 'Notes', { icon: 'box' })
    if (!c.ok) throw new Error('setup failed')
    const r = await setContainerOrder(c.value.path, 'pageType', pageTypeSidecar, 'page_order', ['p2', 'p1'])
    expect(r.ok).toBe(true)
    expect(await readSidecar(c.value.path, 'pageType', pageTypeSidecar)).toMatchObject({
      id: c.value.id,
      icon: 'box',
      page_order: ['p2', 'p1']
    })
  })
})
