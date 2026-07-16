import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile, mkdir, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import type { Tab, TabSet } from '@shared/types'
import { flushTabsWrites, hasPendingTabsWrites, readTabsState, scheduleTabsWrite } from './tabsState'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-tabsstate-'))
})
afterEach(async () => {
  await flushTabsWrites() // drain the module-level debounce so state never leaks across tests
  await rm(root, { recursive: true, force: true })
})

const tabsFile = (): string => join(root, '.nexus', 'tabs.json')
const pageTab = (id: string, pid: string): Tab => ({
  id,
  target: { kind: 'page', id: pid, path: `${pid}.md` },
  navStack: [{ kind: 'page', id: pid, path: `${pid}.md` }],
  navIndex: 0,
})

describe('tabs sidecar — read', () => {
  it('reads null when the file is absent (the store seeds fresh)', async () => {
    expect(await readTabsState(root)).toBeNull()
  })

  it('reads null on corrupt/non-object content', async () => {
    await mkdir(join(root, '.nexus'), { recursive: true })
    await writeFile(tabsFile(), 'garbage{{{', 'utf8')
    expect(await readTabsState(root)).toBeNull()
  })

  it('round-trips a full set (tabs + active + per-tab history) via the debounce + drain', async () => {
    const set: TabSet = {
      tabs: [
        pageTab('t1', 'a'),
        { id: 't2', target: { kind: 'context', id: 'c1' }, navStack: [{ kind: 'homepage' }, { kind: 'context', id: 'c1' }], navIndex: 1 },
        { id: 'n', target: { kind: 'newtab' }, navStack: [], navIndex: -1 },
      ],
      activeTabId: 't2',
    }
    scheduleTabsWrite(root, set)
    await flushTabsWrites()
    expect(await readTabsState(root)).toEqual(set)
  })

  it('drops malformed tabs, degrades a broken history to the target alone', async () => {
    await mkdir(join(root, '.nexus'), { recursive: true })
    const good = pageTab('t1', 'a')
    await writeFile(
      tabsFile(),
      JSON.stringify({
        tabs: [
          good,
          { id: 't2', target: { kind: 'nope', id: 'x' } }, // unknown target kind — dropped
          { target: { kind: 'homepage' } }, // missing id — dropped
          { id: 't3', target: { kind: 'context', id: 'c' }, navStack: 'junk', navIndex: 99 }, // bad history — degrades
        ],
        activeTabId: 't1',
      }),
      'utf8',
    )
    const read = await readTabsState(root)
    expect(read?.tabs).toEqual([
      good,
      { id: 't3', target: { kind: 'context', id: 'c' }, navStack: [{ kind: 'context', id: 'c' }], navIndex: 0 },
    ])
    expect(read?.activeTabId).toBe('t1')
  })

  it('strips newtab sentinels out of a persisted navStack (drivable targets only)', async () => {
    await mkdir(join(root, '.nexus'), { recursive: true })
    await writeFile(
      tabsFile(),
      JSON.stringify({
        tabs: [{ id: 't1', target: { kind: 'homepage' }, navStack: [{ kind: 'newtab' }, { kind: 'homepage' }], navIndex: 1 }],
        activeTabId: 't1',
      }),
      'utf8',
    )
    const read = await readTabsState(root)
    expect(read?.tabs[0].navStack).toEqual([{ kind: 'homepage' }])
    expect(read?.tabs[0].navIndex).toBe(0)
  })
})

describe('tabs sidecar — debounce + drain', () => {
  it('a scheduled write is deferred (pending, nothing on disk) until drained', async () => {
    scheduleTabsWrite(root, { tabs: [pageTab('t1', 'a')], activeTabId: 't1' })
    expect(hasPendingTabsWrites()).toBe(true)
    await expect(readFile(tabsFile(), 'utf8')).rejects.toThrow()
    await flushTabsWrites()
    expect(hasPendingTabsWrites()).toBe(false)
    expect((await readTabsState(root))?.activeTabId).toBe('t1')
  })

  it('scheduled writes coalesce — only the latest payload reaches disk', async () => {
    scheduleTabsWrite(root, { tabs: [pageTab('t1', 'a')], activeTabId: 't1' })
    scheduleTabsWrite(root, { tabs: [pageTab('t2', 'b')], activeTabId: 't2' })
    await flushTabsWrites()
    expect((await readTabsState(root))?.activeTabId).toBe('t2')
  })

  it('flushTabsWrites is a no-op when idle', async () => {
    await flushTabsWrites()
    expect(hasPendingTabsWrites()).toBe(false)
  })
})
