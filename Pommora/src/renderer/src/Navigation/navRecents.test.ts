import { describe, it, expect } from 'vitest'
import type { RecentEntry } from '@shared/types'
import { navKey, recordRecent, removeRecentByKey } from './navRecents'

const page = (id: string): RecentEntry => ({ kind: 'page', id, path: `${id}.md` })

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

  it('rolls off the oldest beyond the cap', () => {
    const start = [page('a'), page('b'), page('c')]
    const r = recordRecent(start, { kind: 'page', id: 'd', path: 'd.md' }, 3)
    expect(r.map((e) => ('id' in e ? e.id : e.kind))).toEqual(['d', 'a', 'b']) // 'c' (oldest) dropped
  })
})

describe('removeRecentByKey', () => {
  it('drops the matching entry, preserving the rest in order', () => {
    const r = removeRecentByKey([page('a'), page('b'), page('c')], 'page:b')
    expect(r.map((e) => ('id' in e ? e.id : e.kind))).toEqual(['a', 'c'])
  })

  it('removes the id-less homepage by bare kind', () => {
    const r = removeRecentByKey([{ kind: 'homepage' }, page('a')], 'homepage')
    expect(r.map((e) => ('id' in e ? e.id : e.kind))).toEqual(['a'])
  })

  it('returns the same reference when nothing matched (no needless persist)', () => {
    const start = [page('a'), page('b')]
    expect(removeRecentByKey(start, 'page:z')).toBe(start)
  })
})
