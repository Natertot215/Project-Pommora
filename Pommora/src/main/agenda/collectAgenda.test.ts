import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { collectAgendaEntries } from './collectAgenda'

let root: string
const d = (p: string): void => {
  mkdirSync(p, { recursive: true })
}
const w = (p: string, c: string): void => {
  writeFileSync(p, c)
}

beforeAll(() => {
  root = mkdtempSync(join(tmpdir(), 'pom-agenda-'))
  const tasks = join(root, 'Tasks')
  d(tasks)
  w(join(tasks, '_taskconfig.json'), '{}')
  w(
    join(tasks, 'Buy milk.task.json'),
    JSON.stringify({ id: 't1', due_at: '2026-07-10T09:00:00.000Z' }),
  )
  const events = join(root, 'Events')
  d(events)
  w(join(events, '_eventconfig.json'), '{}')
  w(
    join(events, 'Standup.event.json'),
    JSON.stringify({
      id: 'e1',
      start_at: '2026-07-08T15:00:00.000Z',
      end_at: '2026-07-08T15:30:00.000Z',
    }),
  )
  // A plain folder with no agenda sidecar must be ignored.
  d(join(root, 'Notes'))
})

afterAll(() => rmSync(root, { recursive: true, force: true }))

describe('collectAgendaEntries', () => {
  it('collects tasks and events from their sidecar folders', async () => {
    const { tasks, events } = await collectAgendaEntries(root)
    expect(tasks.map((t) => t.title)).toContain('Buy milk')
    expect(tasks[0].kind).toBe('task')
    expect(tasks[0].dueAt).toBe('2026-07-10T09:00:00.000Z')
    expect(events.map((e) => e.title)).toContain('Standup')
    expect(events[0].kind).toBe('event')
  })

  it('returns empty arrays for a root with no agenda folders', async () => {
    const bare = mkdtempSync(join(tmpdir(), 'pom-bare-'))
    const { tasks, events } = await collectAgendaEntries(bare)
    expect(tasks).toEqual([])
    expect(events).toEqual([])
    rmSync(bare, { recursive: true, force: true })
  })
})
