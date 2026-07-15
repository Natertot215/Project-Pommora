import { describe, it, expect } from 'vitest'
import type { RecentEntry } from '@shared/types'
import { navKey, recordRecent, togglePinned } from './navRecents'

const page = (id: string, pinned?: boolean): RecentEntry => ({ kind: 'page', id, path: `${id}.md`, ...(pinned ? { pinned } : {}) })

describe('navKey', () => {
  it('keys by kind:id, and by bare kind for the id-less homepage', () => {
    expect(navKey({ kind: 'page', id: 'p1', path: 'p1.md' })).toBe('page:p1')
    expect(navKey({ kind: 'context', id: 'c1' })).toBe('context:c1')
    expect(navKey({ kind: 'homepage' })).toBe('homepage')
  })
})

describe('recordRecent', () => {
  it('moves a visited target to the front (MRU)', () => {
    const r = recordRecent([page('a'), page('b')], { kind: 'page', id: 'b', path: 'b.md' })
    expect(r.map((e) => ('id' in e ? e.id : e.kind))).toEqual(['b', 'a'])
  })

  it('dedupes — a re-visit collapses, no duplicate entry', () => {
    const r = recordRecent([page('a'), page('b')], { kind: 'page', id: 'a', path: 'a.md' })
    expect(r.map((e) => ('id' in e ? e.id : e.kind))).toEqual(['a', 'b'])
    expect(r).toHaveLength(2)
  })

  it('records the id-less homepage', () => {
    const r = recordRecent([page('a')], { kind: 'homepage' })
    expect(r[0]).toEqual({ kind: 'homepage' })
  })

  it('preserves a pinned flag across a re-visit (stays floated)', () => {
    const r = recordRecent([page('a'), page('b', true)], { kind: 'page', id: 'b', path: 'b.md' })
    expect(r[0]).toEqual({ kind: 'page', id: 'b', path: 'b.md', pinned: true })
  })

  it('rolls off the oldest un-pinned beyond the cap', () => {
    const start = [page('a'), page('b'), page('c')]
    const r = recordRecent(start, { kind: 'page', id: 'd', path: 'd.md' }, 3)
    expect(r.map((e) => ('id' in e ? e.id : e.kind))).toEqual(['d', 'a', 'b']) // 'c' (oldest un-pinned) dropped
  })

  it('never rolls off a pinned entry — cap can be exceeded by pins', () => {
    const start = [page('a', true), page('b', true), page('c', true)]
    const r = recordRecent(start, { kind: 'page', id: 'd', path: 'd.md' }, 2)
    expect(r.map((e) => ('id' in e ? e.id : e.kind))).toEqual(['d', 'a', 'b', 'c']) // only 'd' un-pinned; nothing else can drop
  })

  it('drops the oldest UN-pinned, skipping pinned ones, to hit the cap', () => {
    const start = [page('a'), page('b', true), page('c')]
    const r = recordRecent(start, { kind: 'page', id: 'd', path: 'd.md' }, 3)
    expect(r.map((e) => ('id' in e ? e.id : e.kind))).toEqual(['d', 'a', 'b']) // 'c' dropped (oldest un-pinned), 'b' pinned survives
  })
})

describe('togglePinned', () => {
  it('pins an entry (sets pinned: true)', () => {
    const r = togglePinned([page('a'), page('b')], 'page:a')
    expect(r[0]).toEqual({ kind: 'page', id: 'a', path: 'a.md', pinned: true })
  })

  it('un-pins by DELETING the key (no pinned: false persisted)', () => {
    const r = togglePinned([page('a', true)], 'page:a')
    expect(r[0]).toEqual({ kind: 'page', id: 'a', path: 'a.md' })
    expect('pinned' in r[0]).toBe(false)
  })

  it('leaves non-matching entries untouched', () => {
    const start = [page('a'), page('b')]
    const r = togglePinned(start, 'page:a')
    expect(r[1]).toBe(start[1])
  })
})
