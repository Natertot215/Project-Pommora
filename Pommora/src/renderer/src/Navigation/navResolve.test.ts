import { describe, it, expect } from 'vitest'
import type { PinEntry, RecentEntry } from '@shared/types'
import { buildResolveIndex, resolveFavorites, resolveNavEntry, resolvePins, resolveRecents, resolveWith } from './navResolve'
import { makeTree } from './testTree'

describe('resolveNavEntry', () => {
  const pathTitles = (r: { path: { title: string }[] } | null): string[] => (r?.path ?? []).map((c) => c.title)

  it('resolves a page to title + its container-chain path', () => {
    const r = resolveNavEntry(makeTree(), { kind: 'page', id: 'p2', path: 'Notes/Ideas/Beta.md' })
    expect(r).toMatchObject({ kind: 'page', title: 'Nested Beta' })
    expect(pathTitles(r)).toEqual(['Notes', 'Ideas'])
  })

  it('resolves a set to its parent chain (excluding itself)', () => {
    const r = resolveNavEntry(makeTree(), { kind: 'set', id: 's1', path: 'Notes/Ideas' })
    expect(r).toMatchObject({ kind: 'set', title: 'Ideas' })
    expect(pathTitles(r)).toEqual(['Notes'])
  })

  it('resolves a context to its tier label as the path', () => {
    const r = resolveNavEntry(makeTree(), { kind: 'context', id: 't1' })
    expect(r).toMatchObject({ kind: 'context', title: 'Reading' })
    expect(pathTitles(r)).toEqual(['Topic'])
  })

  it('resolves a collection (no path) and homepage', () => {
    const t = makeTree()
    const col = resolveNavEntry(t, { kind: 'collection', id: 'c1' })
    expect(col).toMatchObject({ title: 'Notes' })
    expect(pathTitles(col)).toEqual([])
    expect(resolveNavEntry(t, { kind: 'homepage' })).toMatchObject({ title: 'TestNexus' })
  })

  it('resolves an entry icon for each kind', () => {
    const t = makeTree()
    expect(resolveNavEntry(t, { kind: 'page', id: 'p1', path: 'Notes/Alpha.md' })?.icon).toBeTruthy()
    expect(resolveNavEntry(t, { kind: 'collection', id: 'c1' })?.icon).toBeTruthy()
  })

  it('render-prunes a gone entry (returns null) — never mutates storage', () => {
    expect(resolveNavEntry(makeTree(), { kind: 'page', id: 'ghost', path: 'x.md' })).toBeNull()
    expect(resolveNavEntry(makeTree(), { kind: 'collection', id: 'ghost' })).toBeNull()
  })

  it('resolves agenda kinds to null in v1 (no destination yet)', () => {
    expect(resolveNavEntry(makeTree(), { kind: 'task', id: 'tk1' })).toBeNull()
    expect(resolveNavEntry(makeTree(), { kind: 'event', id: 'ev1' })).toBeNull()
  })

  it('carries the pinned flag through', () => {
    const r = resolveNavEntry(makeTree(), { kind: 'page', id: 'p1', path: 'Notes/Alpha.md', pinned: true })
    expect(r?.pinned).toBe(true)
  })

  it('exposes a CLEAN target (no pinned key leaks into what gets selected/favorited)', () => {
    const r = resolveNavEntry(makeTree(), { kind: 'page', id: 'p1', path: 'Notes/Alpha.md', pinned: true })
    expect(r?.target).toEqual({ kind: 'page', id: 'p1', path: 'Notes/Alpha.md' })
    expect('pinned' in (r?.target ?? {})).toBe(false)
  })
})

describe('buildResolveIndex + resolveWith (index built once, O(1) per entry)', () => {
  it('resolves against a prebuilt index and prunes absent keys', () => {
    const index = buildResolveIndex(makeTree())
    expect(resolveWith(index, { kind: 'page', id: 'p1', path: 'Notes/Alpha.md' })?.title).toBe('Alpha')
    expect(resolveWith(index, { kind: 'page', id: 'ghost', path: 'x.md' })).toBeNull()
    expect(resolveWith(index, { kind: 'task', id: 'tk1' })).toBeNull() // agenda absent from the index
  })
})

describe('resolveRecents', () => {
  it('preserves MRU order (pins are their own list now — no float)', () => {
    const recents: RecentEntry[] = [
      { kind: 'page', id: 'p1', path: 'Notes/Alpha.md' },
      { kind: 'page', id: 'p2', path: 'Notes/Ideas/Beta.md' },
      { kind: 'collection', id: 'c1' }
    ]
    expect(resolveRecents(buildResolveIndex(makeTree()), recents).map((r) => r.key)).toEqual(['page:p1', 'page:p2', 'collection:c1'])
  })

  it('drops gone entries from the render list only', () => {
    const recents: RecentEntry[] = [
      { kind: 'page', id: 'p1', path: 'Notes/Alpha.md' },
      { kind: 'page', id: 'ghost', path: 'x.md' }
    ]
    expect(resolveRecents(buildResolveIndex(makeTree()), recents).map((r) => r.key)).toEqual(['page:p1'])
  })
})

describe('resolveFavorites', () => {
  it('preserves stored order and prunes gone entries', () => {
    const favorites: RecentEntry[] = [
      { kind: 'collection', id: 'c1' },
      { kind: 'collection', id: 'ghost' },
      { kind: 'context', id: 'a1' }
    ]
    expect(resolveFavorites(buildResolveIndex(makeTree()), favorites).map((r) => r.key)).toEqual(['collection:c1', 'context:a1'])
  })
})

describe('resolvePins', () => {
  it('marks each pinned, preserves caller order, prunes gone entries', () => {
    const pins: PinEntry[] = [
      { kind: 'collection', id: 'c1', order: 0 },
      { kind: 'collection', id: 'ghost', order: 1 },
      { kind: 'context', id: 'a1', order: 2 }
    ]
    const out = resolvePins(buildResolveIndex(makeTree()), pins)
    expect(out.map((r) => r.key)).toEqual(['collection:c1', 'context:a1'])
    expect(out.every((r) => r.pinned === true)).toBe(true)
  })
})
