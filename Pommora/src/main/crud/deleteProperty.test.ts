import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile, readdir } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { deleteProperty } from './deleteProperty'
import { createProperty } from './registryProperty'
import { assignProperty } from './assignment'
import { removeProperty } from './removeProperty'
import { createFolderEntity } from './folderEntity'
import { createPage, updatePageProperty } from './page'
import { readRegistry } from '../io/propertiesRegistry'
import { readSidecar } from '../sidecarIO'
import { pageCollectionSidecar } from '@shared/schemas'
import type { PropertyDefinition } from '@shared/properties'

let root: string
let notes: string
let tasks: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-del-'))
  const a = await createFolderEntity(root, 'collection', 'Notes')
  const b = await createFolderEntity(root, 'collection', 'Tasks')
  if (!a.ok || !b.ok) throw new Error('setup failed')
  notes = a.value.path
  tasks = b.value.path
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

describe('deleteProperty', () => {
  it('scrubs the value from every assigner, drops the def + all assignments, and snapshots', async () => {
    const c = await createProperty(root, {
      id: '',
      name: 'Priority',
      type: 'select',
      select_options: [{ value: 'hi', label: 'High', color: 'red' }],
    } as PropertyDefinition)
    expect(c.ok).toBe(true)
    if (!c.ok) return
    const id = c.value.id
    await assignProperty(root, notes, id)
    await assignProperty(root, tasks, id)
    const p1 = await createPage(notes, 'A', { body: 'b' })
    const p2 = await createPage(tasks, 'B', { body: 'b' })
    if (!p1.ok || !p2.ok) return
    await updatePageProperty(p1.value.path, id, { kind: 'select', value: 'hi' })
    await updatePageProperty(p2.value.path, id, { kind: 'select', value: 'hi' })

    expect((await deleteProperty(root, id)).ok).toBe(true)

    // def gone, assignments gone
    expect((await readRegistry(root)).defs[id]).toBeUndefined()
    for (const folder of [notes, tasks]) {
      const sc = await readSidecar(folder, 'collection', pageCollectionSidecar)
      expect(((sc?.properties as string[]) ?? []).includes(id)).toBe(false)
    }
    // frontmatter scrubbed in both, other keys preserved
    for (const path of [p1.value.path, p2.value.path]) {
      const content = await readFile(path, 'utf8')
      expect(content).not.toContain(id)
      expect(content).toContain('id:')
    }
    // a recovery snapshot landed in .trash
    const trashed = await readdir(join(root, '.trash'))
    expect(trashed.some((f) => f.includes(`property-${id}`))).toBe(true)
  })

  it('fails for an unknown property id', async () => {
    expect((await deleteProperty(root, 'prop_nope')).ok).toBe(false)
  })

  it('purges the property_cache block in every sidecar — even non-assigners (D-6)', async () => {
    const c = await createProperty(root, {
      id: '',
      name: 'Priority',
      type: 'select',
      select_options: [{ value: 'hi', label: 'High', color: 'red' }],
    } as PropertyDefinition)
    if (!c.ok) return
    const id = c.value.id
    await assignProperty(root, notes, id)
    const p = await createPage(notes, 'A', { body: 'b' })
    if (!p.ok) return
    await updatePageProperty(p.value.path, id, { kind: 'select', value: 'hi' })
    await removeProperty(notes, id) // notes now holds a cache block and is NOT an assigner

    expect((await deleteProperty(root, id)).ok).toBe(true)

    const sc = await readSidecar(notes, 'collection', pageCollectionSidecar)
    expect((sc?.property_cache as Record<string, unknown> | undefined)?.[id]).toBeUndefined()
    expect((await readRegistry(root)).defs[id]).toBeUndefined()
  })
})
