import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { removeProperty } from './removeProperty'
import { assignProperty } from './assignment'
import { createProperty, editProperty } from './registryProperty'
import { createFolderEntity } from './folderEntity'
import { createPage, updatePageProperty } from './page'
import { readSidecar } from '../sidecarIO'
import { readFrontmatterFields } from '../io/pageFile'
import { pageCollectionSidecar } from '@shared/schemas'
import type { PropertyDefinition } from '@shared/properties'

let root: string
let folder: string
let propId: string
let pageA: string
let pageB: string

const stageDef = {
  id: '',
  name: 'Stage',
  type: 'status',
  status_groups: [
    { id: 'upcoming', label: 'To-do', color: 'gray', options: [{ value: 'active', label: 'Active', group_id: 'upcoming' }] },
    { id: 'done', label: 'Done', color: 'green', options: [{ value: 'done', label: 'Done', group_id: 'done' }] }
  ]
} as PropertyDefinition

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-remove-'))
  const c = await createFolderEntity(root, 'collection', 'Notes')
  const p = await createProperty(root, stageDef)
  if (!c.ok || !p.ok) throw new Error('setup failed')
  folder = c.value.path
  propId = p.value.id
  await assignProperty(root, folder, propId)
  const a = await createPage(folder, 'A', { body: 'b' })
  const b = await createPage(folder, 'B', { body: 'b' })
  if (!a.ok || !b.ok) throw new Error('setup failed')
  pageA = a.value.path
  pageB = b.value.path
  await updatePageProperty(pageA, propId, { kind: 'status', value: 'active' })
  await updatePageProperty(pageB, propId, { kind: 'status', value: 'done' })
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

const pageProps = async (path: string): Promise<Record<string, unknown>> =>
  ((readFrontmatterFields(await readFile(path, 'utf8')).properties as Record<string, unknown> | undefined) ?? {})
const sidecar = async (): Promise<Record<string, unknown> | null> =>
  (await readSidecar(folder, 'collection', pageCollectionSidecar)) as Record<string, unknown> | null
const cacheBlock = async (): Promise<{ removed_at: string; values: Record<string, unknown> } | undefined> =>
  ((await sidecar())?.property_cache as Record<string, { removed_at: string; values: Record<string, unknown> }> | undefined)?.[propId]

describe('removeProperty — strip + cache (C-3/C-6)', () => {
  it('strips the value from every member page, caches {pageId: raw}, and unassigns — one transaction', async () => {
    const r = await removeProperty(folder, propId)
    expect(r.ok).toBe(true)
    expect(await pageProps(pageA)).toEqual({})
    expect(await pageProps(pageB)).toEqual({})
    const sc = await sidecar()
    expect(((sc?.properties as string[] | undefined) ?? [])).not.toContain(propId)
    const block = await cacheBlock()
    expect(typeof block?.removed_at).toBe('string')
    const vals = Object.values(block?.values ?? {})
    expect(vals).toHaveLength(2)
    expect(vals).toEqual(expect.arrayContaining([{ $status: 'active' }, { $status: 'done' }]))
  })

  it('is a no-op when the property is not assigned — never overwrites a cache with emptiness (E-6)', async () => {
    await removeProperty(folder, propId)
    const before = await cacheBlock()
    const again = await removeProperty(folder, propId)
    expect(again.ok).toBe(true)
    expect(await cacheBlock()).toEqual(before)
  })
})

describe('restore on re-assign — per-value schema-currency reconciliation (C-3)', () => {
  it('restores cached values to pages still present and clears the block', async () => {
    await removeProperty(folder, propId)
    const r = await assignProperty(root, folder, propId)
    expect(r.ok).toBe(true)
    expect(await pageProps(pageA)).toEqual({ [propId]: { $status: 'active' } })
    expect(await pageProps(pageB)).toEqual({ [propId]: { $status: 'done' } })
    expect(await cacheBlock()).toBeUndefined()
    expect((await sidecar())?.properties).toContain(propId)
  })

  it('drops a value whose option no longer exists; keeps conforming siblings', async () => {
    await removeProperty(folder, propId)
    await editProperty(root, propId, {
      status_groups: [
        { id: 'done', label: 'Done', color: 'green', options: [{ value: 'done', label: 'Done', group_id: 'done' }] }
      ]
    } as Partial<PropertyDefinition>)
    await assignProperty(root, folder, propId)
    expect(await pageProps(pageA)).toEqual({}) // 'active' is no longer a live option
    expect(await pageProps(pageB)).toEqual({ [propId]: { $status: 'done' } })
    expect(await cacheBlock()).toBeUndefined()
  })

  it('drops a value whose def type changed since caching', async () => {
    await removeProperty(folder, propId)
    await editProperty(root, propId, { type: 'number' })
    await assignProperty(root, folder, propId)
    expect(await pageProps(pageA)).toEqual({})
    expect(await pageProps(pageB)).toEqual({})
    expect(await cacheBlock()).toBeUndefined()
  })

  it('a page deleted while cached is skipped — entry dropped, no error', async () => {
    await removeProperty(folder, propId)
    await rm(pageA)
    const r = await assignProperty(root, folder, propId)
    expect(r.ok).toBe(true)
    expect(await pageProps(pageB)).toEqual({ [propId]: { $status: 'done' } })
    expect(await cacheBlock()).toBeUndefined()
  })
})
