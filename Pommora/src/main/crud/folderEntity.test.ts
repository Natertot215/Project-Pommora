import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, stat, readdir } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import {
  createFolderEntity,
  renameFolderEntity,
  deleteFolderEntity,
  updateFolderSidecar
} from './folderEntity'
import { readSidecar } from '../sidecarIO'
import { areaSidecar, pageCollectionSidecar } from '@shared/schemas'
import { isUlid } from '../ids'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-crud-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

describe('createFolderEntity', () => {
  it('creates a folder + sidecar with a fresh ULID (one factory for all kinds)', async () => {
    const r = await createFolderEntity(root, 'area', 'Health', { tier: 1, color: 'green' })
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(isUlid(r.value.id)).toBe(true)
    expect(await readSidecar(r.value.path, 'area', areaSidecar)).toMatchObject({
      id: r.value.id,
      tier: 1,
      color: 'green'
    })
  })

  it('rejects a duplicate name', async () => {
    await createFolderEntity(root, 'collection','Notes')
    expect((await createFolderEntity(root, 'collection','Notes')).ok).toBe(false)
  })

  it('rejects unsafe names', async () => {
    expect((await createFolderEntity(root, 'collection','a/b')).ok).toBe(false)
    expect((await createFolderEntity(root, 'collection','..')).ok).toBe(false)
    expect((await createFolderEntity(root, 'collection','   ')).ok).toBe(false)
  })
})

describe('renameFolderEntity', () => {
  it('renames the folder, carrying the sidecar', async () => {
    const c = await createFolderEntity(root, 'collection','Old')
    if (!c.ok) throw new Error('setup failed')
    const r = await renameFolderEntity(c.value.path, 'New')
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.value.path.endsWith('New')).toBe(true)
    await expect(stat(c.value.path)).rejects.toThrow()
    expect(await readSidecar(r.value.path, 'collection', pageCollectionSidecar)).toMatchObject({ id: c.value.id })
  })

  it('is a no-op when the name is unchanged', async () => {
    const c = await createFolderEntity(root, 'collection','Same')
    if (!c.ok) throw new Error('setup failed')
    expect((await renameFolderEntity(c.value.path, 'Same')).ok).toBe(true)
  })

  it('rejects renaming onto an existing name', async () => {
    const a = await createFolderEntity(root, 'collection','A')
    await createFolderEntity(root, 'collection','B')
    if (!a.ok) throw new Error('setup failed')
    expect((await renameFolderEntity(a.value.path, 'B')).ok).toBe(false)
  })
})

describe('deleteFolderEntity', () => {
  it('moves the folder into .trash and removes the original', async () => {
    const c = await createFolderEntity(root, 'collection','Trashme')
    if (!c.ok) throw new Error('setup failed')
    expect((await deleteFolderEntity(root, c.value.path)).ok).toBe(true)
    await expect(stat(c.value.path)).rejects.toThrow()
    const trashed = await readdir(join(root, '.trash'))
    expect(trashed.some((n) => n.includes('Trashme'))).toBe(true)
  })
})

describe('updateFolderSidecar', () => {
  it('merges a patch while preserving foreign keys', async () => {
    const c = await createFolderEntity(root, 'area', 'Money', { tier: 1, color: 'blue', plugin: 'keep' })
    if (!c.ok) throw new Error('setup failed')
    expect((await updateFolderSidecar(c.value.path, 'area', areaSidecar, { color: 'red' })).ok).toBe(true)
    expect(await readSidecar(c.value.path, 'area', areaSidecar)).toMatchObject({
      id: c.value.id,
      tier: 1,
      color: 'red',
      plugin: 'keep'
    })
  })

  it('errors when the sidecar is missing', async () => {
    const r = await updateFolderSidecar(join(root, 'nope'), 'area', areaSidecar, { color: 'red' })
    expect(r.ok).toBe(false)
  })
})
