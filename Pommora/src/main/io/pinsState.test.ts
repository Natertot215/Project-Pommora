import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import type { PinEntry } from '@shared/types'
import { readPins, writePin, removePin, pinFileName } from './pinsState'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-pins-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

const pin = (over: Partial<PinEntry> = {}): PinEntry => ({ kind: 'collection', id: 'c1', order: 0, ...over }) as PinEntry

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
    expect((await readPins(root)).map((p) => p.id)).toEqual(['z', 'a', 'b'])
  })
})
