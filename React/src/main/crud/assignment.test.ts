import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { assignProperty, reorderAssignment, allCollectionFolders } from './assignment'
import { createFolderEntity } from './folderEntity'
import { readSidecar } from '../sidecarIO'
import { pageCollectionSidecar } from '@shared/schemas'

let root: string
let notes: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-assign-'))
  const c = await createFolderEntity(root, 'collection', 'Notes')
  if (!c.ok) throw new Error('setup failed')
  notes = c.value.path
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

const ids = async (folder: string): Promise<string[]> =>
  ((await readSidecar(folder, 'collection', pageCollectionSidecar))?.properties as string[]) ?? []

it('assign appends + is idempotent', async () => {
  await assignProperty(root, notes, 'prop_x')
  await assignProperty(root, notes, 'prop_x')
  expect(await ids(notes)).toEqual(['prop_x'])
})

it('reorder moves within the assignment array', async () => {
  await assignProperty(root, notes, 'prop_a')
  await assignProperty(root, notes, 'prop_b')
  await assignProperty(root, notes, 'prop_c')
  await reorderAssignment(notes, 'prop_c', 0)
  expect(await ids(notes)).toEqual(['prop_c', 'prop_a', 'prop_b'])
})

it('allCollectionFolders walks every collection folder in the tree', async () => {
  const t = await createFolderEntity(root, 'collection', 'Tasks')
  if (!t.ok) throw new Error('setup failed')
  expect((await allCollectionFolders(root)).sort()).toEqual([notes, t.value.path].sort())
})
