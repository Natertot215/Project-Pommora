import { mkdtemp, readFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { debouncedSidecar } from './debouncedSidecar'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'sidecar-'))
})
afterEach(() => rm(root, { recursive: true, force: true }))

const make = (debounceMs = 50) =>
  debouncedSidecar<{ v: number }>({
    path: (r) => join(r, '.nexus', 'probe.json'),
    debounceMs,
    label: 'probe',
  })

const read = async (): Promise<unknown> =>
  JSON.parse(await readFile(join(root, '.nexus', 'probe.json'), 'utf8'))

describe('debouncedSidecar — the drain contract', () => {
  it('a burst coalesces to one write: only the newest payload reaches disk', async () => {
    const s = make()
    s.schedule(root, { v: 1 })
    s.schedule(root, { v: 2 })
    s.schedule(root, { v: 3 })
    expect(s.hasQueued()).toBe(true)
    await s.flush()
    expect(await read()).toEqual({ v: 3 })
    expect(s.hasPending()).toBe(false)
  })

  it('writeNow cancels the queued payload so a stale one never lands after it', async () => {
    const s = make(10_000)
    s.schedule(root, { v: 1 })
    await s.writeNow(root, { v: 2 })
    expect(s.hasQueued()).toBe(false)
    await s.flush()
    expect(await read()).toEqual({ v: 2 })
  })

  it('tracked external writes hold the drain open until they settle', async () => {
    const s = make()
    let release!: () => void
    const external = new Promise<void>((r) => {
      release = r
    })
    s.track(external)
    expect(s.hasPending()).toBe(true)
    const drained = s.flush().then(() => (s.hasPending() ? 'still-owed' : 'dry'))
    release()
    expect(await drained).toBe('dry')
  })

  it('a payload scheduled mid-drain is caught by the loop', async () => {
    const s = make()
    s.schedule(root, { v: 1 })
    const drain = s.flush()
    s.schedule(root, { v: 2 })
    await drain
    expect(await read()).toEqual({ v: 2 })
    expect(s.hasPending()).toBe(false)
  })
})
