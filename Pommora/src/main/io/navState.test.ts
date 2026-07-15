import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import type { NavFavorite, RecentEntry } from '@shared/types'
import { flushNavWrites, flushRecents, hasPendingNavWrites, hasPendingRecents, readNavState, scheduleRecentsWrite, writeFavorites, writeRecentsNow } from './navState'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-navstate-'))
})
afterEach(async () => {
  await flushRecents() // drain the module-level debounce so state never leaks across tests
  await rm(root, { recursive: true, force: true })
})

const readRaw = async (file: string): Promise<unknown> => JSON.parse(await readFile(join(root, '.nexus', file), 'utf8'))

describe('nav sidecars — reads', () => {
  it('reads empty when both files are absent', async () => {
    expect(await readNavState(root)).toEqual({ recents: [], favorites: [] })
  })

  it('drops malformed entries (bad kind, missing id, missing path, non-boolean pinned)', async () => {
    const good: RecentEntry = { kind: 'page', id: 'p1', path: 'a/b.md', pinned: true }
    const junk: unknown[] = [
      good,
      { kind: 'nope', id: 'x' }, // unknown kind
      { kind: 'collection' }, // missing id
      { kind: 'page', id: 'p2' }, // page missing path
      { kind: 'page', id: 'p3', path: 'c.md', pinned: 'yes' }, // pinned not boolean
      'garbage'
    ]
    await writeRecentsNow(root, junk as RecentEntry[])
    expect((await readNavState(root)).recents).toEqual([good])
  })

  it('keeps a homepage entry (id-less) and preserves order', async () => {
    const recents: RecentEntry[] = [{ kind: 'homepage' }, { kind: 'context', id: 'c1' }, { kind: 'set', id: 's1', path: 's/x' }]
    await writeRecentsNow(root, recents)
    expect((await readNavState(root)).recents).toEqual(recents)
  })
})

describe('favorites — immediate write', () => {
  it('round-trips to .nexus/navFavorites.json', async () => {
    const favorites: NavFavorite[] = [{ kind: 'collection', id: 'c1' }, { kind: 'homepage' }]
    await writeFavorites(root, favorites)
    expect(await readRaw('navFavorites.json')).toEqual(favorites)
    expect((await readNavState(root)).favorites).toEqual(favorites)
  })
})

describe('recents — debounce + immediate + flush', () => {
  it('a scheduled write is deferred (pending, nothing on disk yet) until flushed', async () => {
    scheduleRecentsWrite(root, [{ kind: 'page', id: 'p1', path: 'a.md' }])
    expect(hasPendingRecents()).toBe(true)
    await expect(readFile(join(root, '.nexus', 'navRecents.json'), 'utf8')).rejects.toThrow()
    await flushRecents()
    expect(hasPendingRecents()).toBe(false)
    expect((await readNavState(root)).recents).toEqual([{ kind: 'page', id: 'p1', path: 'a.md' }])
  })

  it('scheduled writes coalesce — only the latest pending payload reaches disk', async () => {
    scheduleRecentsWrite(root, [{ kind: 'page', id: 'p1', path: 'a.md' }])
    scheduleRecentsWrite(root, [{ kind: 'page', id: 'p2', path: 'b.md' }])
    await flushRecents()
    expect((await readNavState(root)).recents).toEqual([{ kind: 'page', id: 'p2', path: 'b.md' }])
  })

  it('writeRecentsNow supersedes a pending scheduled write — the stale payload can never land', async () => {
    scheduleRecentsWrite(root, [{ kind: 'page', id: 'stale', path: 'a.md' }])
    await writeRecentsNow(root, [{ kind: 'page', id: 'fresh', path: 'b.md' }])
    expect(hasPendingRecents()).toBe(false) // pending cleared, so a later flush is a no-op
    await flushRecents()
    expect((await readNavState(root)).recents).toEqual([{ kind: 'page', id: 'fresh', path: 'b.md' }])
  })

  it('flushRecents is a no-op when nothing is pending', async () => {
    await flushRecents()
    expect(hasPendingRecents()).toBe(false)
  })
})

describe('quit-drain gate — every owed write, not just the debounce', () => {
  it('an in-flight immediate write (favorite/pin) is visible to the gate and drained by flushNavWrites', async () => {
    const p = writeFavorites(root, [{ kind: 'homepage' }]) // deliberately not awaited — still settling
    expect(hasPendingNavWrites()).toBe(true)
    await flushNavWrites()
    expect(hasPendingNavWrites()).toBe(false)
    await p
    expect((await readNavState(root)).favorites).toEqual([{ kind: 'homepage' }])
  })

  it('flushNavWrites drains a queued debounce too', async () => {
    scheduleRecentsWrite(root, [{ kind: 'context', id: 'c1' }])
    expect(hasPendingNavWrites()).toBe(true)
    await flushNavWrites()
    expect(hasPendingNavWrites()).toBe(false)
    expect((await readNavState(root)).recents).toEqual([{ kind: 'context', id: 'c1' }])
  })

  it('hasPendingNavWrites is false and flushNavWrites is a no-op when idle', async () => {
    await flushNavWrites()
    expect(hasPendingNavWrites()).toBe(false)
  })
})
