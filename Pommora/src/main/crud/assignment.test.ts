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

it('a Remove racing an Assign on ONE collection never loses either write (breaker H-2)', async () => {
  const { createProperty } = await import('./registryProperty')
  const { removeProperty } = await import('./removeProperty')
  const { createPage, updatePageProperty } = await import('./page')
  const { readFile } = await import('node:fs/promises')
  const { readFrontmatterFields } = await import('../io/pageFile')
  const mk = async (name: string): Promise<string> => {
    const r = await createProperty(root, { id: '', name, type: 'number' } as never)
    if (!r.ok) throw new Error('setup failed')
    return r.value.id
  }
  const pC = await mk('Gone')
  const pB = await mk('Incoming')
  await assignProperty(root, notes, pC)
  const page = await createPage(notes, 'A', { body: 'b' })
  if (!page.ok) throw new Error('setup failed')
  await updatePageProperty(page.value.path, pC, { kind: 'number', value: 7 })

  // Interleave 20 rounds — under the serialized chain the end state is always coherent:
  // pC unassigned WITH its cache block intact, pB assigned.
  for (let round = 0; round < 20; round++) {
    await Promise.all([removeProperty(notes, pC), assignProperty(root, notes, pB)])
    const sc = (await readSidecar(notes, 'collection', pageCollectionSidecar)) as Record<
      string,
      unknown
    >
    const assigned = (sc.properties as string[]) ?? []
    const cached = (
      sc.property_cache as Record<string, { values: Record<string, unknown> }> | undefined
    )?.[pC]
    expect(assigned).toContain(pB)
    expect(assigned).not.toContain(pC)
    expect(Object.values(cached?.values ?? {})).toEqual([7])
    const props = readFrontmatterFields(await readFile(page.value.path, 'utf8')).properties as
      | Record<string, unknown>
      | undefined
    expect(props?.[pC]).toBeUndefined()
    // reset for the next round: re-assign restores the value, unassign pB
    await assignProperty(root, notes, pC)
    await removeProperty(notes, pB)
  }
})
