import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { assignProperty, unassignProperty, reorderAssignment, assigners } from './assignment'
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
  await assignProperty(notes, 'prop_x')
  await assignProperty(notes, 'prop_x')
  expect(await ids(notes)).toEqual(['prop_x'])
})

it('unassign removes just that id', async () => {
  await assignProperty(notes, 'prop_x')
  await assignProperty(notes, 'prop_y')
  await unassignProperty(notes, 'prop_x')
  expect(await ids(notes)).toEqual(['prop_y'])
})

it('reorder moves within the assignment array', async () => {
  await assignProperty(notes, 'prop_a')
  await assignProperty(notes, 'prop_b')
  await assignProperty(notes, 'prop_c')
  await reorderAssignment(notes, 'prop_c', 0)
  expect(await ids(notes)).toEqual(['prop_c', 'prop_a', 'prop_b'])
})

it('assigners finds every collection folder assigning the id', async () => {
  const t = await createFolderEntity(root, 'collection', 'Tasks')
  if (!t.ok) throw new Error('setup failed')
  const tasks = t.value.path
  await assignProperty(notes, 'prop_shared')
  await assignProperty(tasks, 'prop_shared')
  await assignProperty(tasks, 'prop_only')
  expect((await assigners(root, 'prop_shared')).sort()).toEqual([notes, tasks].sort())
  expect(await assigners(root, 'prop_only')).toEqual([tasks])
  expect(await assigners(root, 'prop_none')).toEqual([])
})
