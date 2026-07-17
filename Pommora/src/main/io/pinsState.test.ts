import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { writeFile, mkdir } from 'node:fs/promises'
import type { PinEntry, RecentEntry } from '@shared/types'
import { readPins, writePin, removePin, pinFileName, loadOrMigratePins } from './pinsState'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-pins-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

const pin = (over: Partial<PinEntry> = {}): PinEntry =>
  ({ kind: 'collection', id: 'c1', order: 0, ...over }) as PinEntry

describe('pinsState', () => {
  it('round-trips a pin', async () => {
    await writePin(root, pin())
    expect(await readPins(root)).toEqual([pin()])
  })

  it('sanitizes the colon out of the filename', () => {
    expect(pinFileName({ kind: 'collection', id: 'c1' })).toBe('collection-c1')
    expect(pinFileName({ kind: 'homepage' })).toBe('homepage')
  })

  it('drops a tombstoned pin on read', async () => {
    await writePin(root, pin())
    await removePin(root, { kind: 'collection', id: 'c1' }, 0)
    expect(await readPins(root)).toEqual([])
  })

  it('reads nothing from a missing dir', async () => {
    expect(await readPins(root)).toEqual([])
  })

  it('sorts by order, then filename on a tie', async () => {
    await writePin(root, pin({ id: 'b', order: 1 }))
    await writePin(root, pin({ id: 'a', order: 1 }))
    await writePin(root, pin({ id: 'z', order: 0 }))
    expect((await readPins(root)).map((p) => ('id' in p ? p.id : ''))).toEqual(['z', 'a', 'b'])
  })

  const writeRecents = async (entries: RecentEntry[]): Promise<void> => {
    await mkdir(join(root, '.nexus'), { recursive: true })
    await writeFile(join(root, '.nexus', 'navRecents.json'), JSON.stringify(entries), 'utf8')
  }

  it('migrates legacy pinned recents on first load (dir absent), order-preserving', async () => {
    await writeRecents([
      { kind: 'page', id: 'a', path: '/a', pinned: true },
      { kind: 'page', id: 'b', path: '/b' },
      { kind: 'context', id: 'x', pinned: true },
    ])
    const pins = await loadOrMigratePins(root)
    expect(pins.map((p) => ('id' in p ? p.id : ''))).toEqual(['a', 'x'])
    expect(pins[0].order).toBeLessThan(pins[1].order)
  })

  it('does NOT re-migrate once the pins dir exists (tombstone sentinel)', async () => {
    await writeRecents([{ kind: 'page', id: 'a', path: '/a', pinned: true }])
    await loadOrMigratePins(root) // first run migrates
    await removePin(root, { kind: 'page', id: 'a', path: '/a' }, 0) // unpin — dir now holds a tombstone
    expect(await loadOrMigratePins(root)).toEqual([]) // stale flag ignored, no resurrection
  })
})
