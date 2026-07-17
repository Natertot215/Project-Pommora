import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import {
  addAgendaProperty,
  renameAgendaProperty,
  deleteAgendaProperty,
  changeAgendaPropertyType,
} from './schema'
import { createFolderEntity } from './folderEntity'
import { createAgendaItem, updateAgendaProperty } from './agendaEntity'
import { readSidecar } from '../sidecarIO'
import { agendaConfigSidecar } from '@shared/schemas'
import { parseDefinitions } from '../properties/schema'
import { defaultStatusSeed, type PropertyDefinition } from '@shared/properties'

let root: string
let tasks: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-agenda-schema-'))
  const cfg = await createFolderEntity(root, 'taskConfig', 'Tasks', {
    property_definitions: [
      { id: '_status', name: 'Status', type: 'status', status_groups: defaultStatusSeed() },
    ],
    schema_version: 1,
  })
  if (!cfg.ok) throw new Error('setup')
  tasks = cfg.value.path
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

const defs = async (): Promise<PropertyDefinition[]> =>
  parseDefinitions(
    (await readSidecar(tasks, 'taskConfig', agendaConfigSidecar))?.property_definitions,
  )
const props = async (p: string): Promise<Record<string, unknown>> =>
  (JSON.parse(await readFile(p, 'utf8')).properties ?? {}) as Record<string, unknown>

describe('agenda config schema CRUD', () => {
  it('adds + renames a property on the task config (sidecar-only)', async () => {
    const a = await addAgendaProperty(tasks, 'task', {
      id: '',
      name: 'Effort',
      type: 'number',
    } as PropertyDefinition)
    expect(a.ok).toBe(true)
    if (!a.ok) return
    expect((await defs()).map((d) => d.name)).toEqual(['Status', 'Effort'])
    expect((await renameAgendaProperty(tasks, 'task', a.value.id, 'Points')).ok).toBe(true)
    expect((await defs()).find((d) => d.id === a.value.id)?.name).toBe('Points')
  })

  it('deletes a property and strips its value from every task item (JSON member strip)', async () => {
    const a = await addAgendaProperty(tasks, 'task', {
      id: '',
      name: 'Effort',
      type: 'number',
    } as PropertyDefinition)
    if (!a.ok) return
    const t1 = await createAgendaItem(tasks, 'task', 'T1')
    if (!t1.ok) return
    await updateAgendaProperty(t1.value.path, a.value.id, { kind: 'number', value: 3 })
    expect((await props(t1.value.path))[a.value.id]).toBe(3)

    expect((await deleteAgendaProperty(tasks, 'task', a.value.id)).ok).toBe(true)
    expect((await defs()).some((d) => d.id === a.value.id)).toBe(false)
    expect((await props(t1.value.path))[a.value.id]).toBeUndefined() // stripped from the item
  })

  it('gates a lossy type change, then strips on confirm', async () => {
    const a = await addAgendaProperty(tasks, 'task', {
      id: '',
      name: 'Effort',
      type: 'number',
    } as PropertyDefinition)
    if (!a.ok) return
    const t1 = await createAgendaItem(tasks, 'task', 'T1')
    if (!t1.ok) return
    await updateAgendaProperty(t1.value.path, a.value.id, { kind: 'number', value: 3 })

    expect((await changeAgendaPropertyType(tasks, 'task', a.value.id, 'url')).ok).toBe(false)
    expect(
      (
        await changeAgendaPropertyType(tasks, 'task', a.value.id, 'url', {
          dropConflictingValues: true,
        })
      ).ok,
    ).toBe(true)
    expect((await defs()).find((d) => d.id === a.value.id)?.type).toBe('url')
    expect((await props(t1.value.path))[a.value.id]).toBeUndefined()
  })
})
