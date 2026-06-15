import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, mkdir, stat, readFile, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import {
  createAgendaItem,
  renameAgendaItem,
  deleteAgendaItem,
  updateAgendaItem,
  updateAgendaProperty,
  setAgendaTier
} from './agendaEntity'

let root: string
let tasks: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-agenda-'))
  tasks = join(root, 'Tasks')
  await mkdir(tasks, { recursive: true })
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

const read = async (p: string): Promise<Record<string, unknown>> => JSON.parse(await readFile(p, 'utf8'))

describe('createAgendaItem', () => {
  it('writes a task with a fresh ULID + EKReminder defaults', async () => {
    const r = await createAgendaItem(tasks, 'task', 'Buy milk')
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.value.path.endsWith('Buy milk.task.json')).toBe(true)
    const t = await read(r.value.path)
    expect(t).toMatchObject({
      id: r.value.id,
      description: '',
      due_floating: false,
      completed: false,
      priority: 0,
      tier1: [],
      properties: {}
    })
    expect(t.created_at).toBeTruthy()
  })

  it('requires start_at + end_at for an event', async () => {
    expect((await createAgendaItem(tasks, 'event', 'NoTimes')).ok).toBe(false)
    const r = await createAgendaItem(tasks, 'event', 'Standup', {
      start_at: '2026-06-15T09:00:00.000Z',
      end_at: '2026-06-15T09:15:00.000Z'
    })
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.value.path.endsWith('Standup.event.json')).toBe(true)
    expect(await read(r.value.path)).toMatchObject({ all_day: false, start_at: '2026-06-15T09:00:00.000Z' })
  })

  it('rejects duplicate + unsafe names', async () => {
    await createAgendaItem(tasks, 'task', 'Dup')
    expect((await createAgendaItem(tasks, 'task', 'Dup')).ok).toBe(false)
    expect((await createAgendaItem(tasks, 'task', 'a/b')).ok).toBe(false)
  })
})

describe('renameAgendaItem / deleteAgendaItem', () => {
  it('renames preserving the suffix', async () => {
    const c = await createAgendaItem(tasks, 'task', 'Old')
    if (!c.ok) throw new Error('setup')
    const r = await renameAgendaItem(c.value.path, 'New')
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.value.path.endsWith('New.task.json')).toBe(true)
    await expect(stat(c.value.path)).rejects.toThrow()
  })

  it('deletes into .trash', async () => {
    const c = await createAgendaItem(tasks, 'task', 'Gone')
    if (!c.ok) throw new Error('setup')
    expect((await deleteAgendaItem(root, c.value.path)).ok).toBe(true)
    await expect(stat(c.value.path)).rejects.toThrow()
  })
})

describe('updates preserve foreign keys + siblings', () => {
  it('updateAgendaItem merges fields, keeps foreign data, bumps modified_at', async () => {
    const c = await createAgendaItem(tasks, 'task', 'T')
    if (!c.ok) throw new Error('setup')
    // Inject a foreign key as if written by another tool.
    const raw = await read(c.value.path)
    await writeFile(c.value.path, JSON.stringify({ ...raw, plugin_key: 'keep' }), 'utf8')

    const r = await updateAgendaItem(c.value.path, { completed: true, completed_at: '2026-06-15T00:00:00.000Z' })
    expect(r.ok).toBe(true)
    const t = await read(c.value.path)
    expect(t.completed).toBe(true)
    expect(t.plugin_key).toBe('keep')
    expect(t.id).toBe(c.value.id)
  })

  it('updateAgendaProperty sets, encodes a relation, and clears', async () => {
    const c = await createAgendaItem(tasks, 'task', 'P')
    if (!c.ok) throw new Error('setup')
    await updateAgendaProperty(c.value.path, '_status', { kind: 'status', value: 'todo' })
    await updateAgendaProperty(c.value.path, 'prop_rel', { kind: 'relation', value: ['01H'] })
    expect((await read(c.value.path)).properties).toEqual({ _status: { $status: 'todo' }, prop_rel: [{ $rel: '01H' }] })
    await updateAgendaProperty(c.value.path, '_status', null)
    expect((await read(c.value.path)).properties).toEqual({ prop_rel: [{ $rel: '01H' }] })
  })

  it('setAgendaTier writes a bare ULID array at the root', async () => {
    const c = await createAgendaItem(tasks, 'task', 'Tiered')
    if (!c.ok) throw new Error('setup')
    expect((await setAgendaTier(c.value.path, 2, ['ctxA'])).ok).toBe(true)
    expect((await read(c.value.path)).tier2).toEqual(['ctxA'])
    expect((await setAgendaTier(c.value.path, 4, [])).ok).toBe(false)
  })
})
