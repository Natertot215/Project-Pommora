import { describe, it, expect } from 'vitest'
import type { PinEntry, RecentEntry } from '@shared/types'
import { pinFor, reorderTo, migratePinnedRecents, cleanPinTarget } from './navPins'
import { navKey } from './navRecents'

const p = (id: string, order: number): PinEntry => ({ kind: 'page', id, path: `/${id}`, order }) as PinEntry

describe('navPins', () => {
  it('appends a new pin above the current max order', () => {
    const next = pinFor({ kind: 'page', id: 'z', path: '/z' }, [p('a', 0), p('b', 1)])
    expect(next.order).toBeGreaterThan(1)
    expect(navKey(next)).toBe('page:z')
  })

  it('seeds the first pin at 0', () => {
    expect(pinFor({ kind: 'homepage' }, []).order).toBe(0)
  })

  it('reorders to a fractional order between the new neighbors', () => {
    const moved = reorderTo([p('a', 0), p('b', 1), p('c', 2)], navKey({ kind: 'page', id: 'c' }), navKey({ kind: 'page', id: 'a' }))
    expect(moved).not.toBeNull()
    expect(moved!.order).toBeLessThan(0) // dropped before 'a'
    expect(navKey(moved!)).toBe('page:c')
  })

  it('returns null when active === over (no-op)', () => {
    expect(reorderTo([p('a', 0)], 'page:a', 'page:a')).toBeNull()
  })

  it('migrates pinned recents to ordered pins, dropping the flag and unpinned entries', () => {
    const recents: RecentEntry[] = [
      { kind: 'page', id: 'a', path: '/a', pinned: true },
      { kind: 'page', id: 'b', path: '/b' },
      { kind: 'context', id: 'x', pinned: true }
    ]
    const pins = migratePinnedRecents(recents)
    expect(pins.map((x) => navKey(x))).toEqual(['page:a', 'context:x'])
    expect(pins[0].order).toBeLessThan(pins[1].order)
    expect((pins[0] as { pinned?: boolean }).pinned).toBeUndefined()
  })

  it('strips order/deleted down to a clean target', () => {
    expect(cleanPinTarget({ kind: 'page', id: 'a', path: '/a', order: 3, deleted: false } as PinEntry)).toEqual({ kind: 'page', id: 'a', path: '/a' })
  })
})
