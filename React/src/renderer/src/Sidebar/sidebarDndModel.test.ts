import { describe, it, expect } from 'vitest'
import { buildIndex, nextOrder, setContainerOf, isSelfOrDescendant, slotInGroup, type Entry, type MeasuredRow } from './sidebarDndModel'
import type { AreaNode, CollectionNode, NexusTree } from '@shared/types'

// 1 Collection → (loose page P3) + Set s1 [P1, P2] → Sub-Set s2 [P5], plus two Areas (contexts).
const collections: CollectionNode[] = [
  {
    id: 'c1',
    kind: 'collection',
    title: 'Col',
    path: 'Col',
    pages: [{ id: 'p3', kind: 'page', title: 'P3', path: 'Col/P3.md' }],
    sets: [
      {
        id: 's1',
        kind: 'set',
        title: 'Set',
        path: 'Col/Set',
        pages: [
          { id: 'p1', kind: 'page', title: 'P1', path: 'Col/Set/P1.md' },
          { id: 'p2', kind: 'page', title: 'P2', path: 'Col/Set/P2.md' }
        ],
        sets: [
          {
            id: 's2',
            kind: 'set',
            title: 'Sub',
            path: 'Col/Set/Sub',
            pages: [{ id: 'p5', kind: 'page', title: 'P5', path: 'Col/Set/Sub/P5.md' }]
          }
        ]
      }
    ]
  }
]
const areas: AreaNode[] = [
  { id: 'a1', kind: 'area', title: 'Work', path: '.nexus/areas/Work' },
  { id: 'a2', kind: 'area', title: 'Home', path: '.nexus/areas/Home' }
]
const tree = { vaults: [], collections, userSections: [], contexts: { areas, topics: [], projects: [] } } as unknown as NexusTree

describe('buildIndex', () => {
  const idx = buildIndex(tree)
  it('indexes containers with child page ids, child container ids + render depth', () => {
    expect(idx.byId.get('c1')).toMatchObject({ kind: 'collection', depth: 0, pageIds: ['p3'], containerIds: ['s1'] })
    expect(idx.byId.get('s1')).toMatchObject({ kind: 'set', depth: 1, pageIds: ['p1', 'p2'], containerIds: ['s2'] })
    expect(idx.byId.get('s2')).toMatchObject({ kind: 'set', depth: 2, pageIds: ['p5'], containerIds: [] })
  })
  it('indexes pages with their parent container + render depth', () => {
    expect(idx.byId.get('p1')).toMatchObject({ kind: 'page', depth: 2, parentId: 's1', parentPath: 'Col/Set' })
    expect(idx.byId.get('p3')).toMatchObject({ kind: 'page', depth: 1, parentId: 'c1', parentPath: 'Col' })
    expect(idx.byId.get('p5')).toMatchObject({ kind: 'page', depth: 3, parentId: 's2', parentPath: 'Col/Set/Sub' })
  })
  it('exposes top-level groups + indexes contexts as depth-1 leaves (nested under their tier)', () => {
    expect(idx.collectionIds).toEqual(['c1'])
    expect(idx.areaIds).toEqual(['a1', 'a2'])
    expect(idx.byId.get('a1')).toMatchObject({ kind: 'area', depth: 1, parentId: null })
  })
})

describe('nextOrder', () => {
  it('reorders within a group (to front / further back)', () => {
    expect(nextOrder(['a', 'b', 'c'], 'c', 'a')).toEqual(['c', 'a', 'b'])
    expect(nextOrder(['a', 'b', 'c'], 'a', 'c')).toEqual(['b', 'a', 'c'])
  })
  it('appends when beforeId is null', () => {
    expect(nextOrder(['a', 'b', 'c'], 'a', null)).toEqual(['b', 'c', 'a'])
  })
  it('inserts an item arriving from elsewhere', () => {
    expect(nextOrder(['x', 'y'], 'd', 'y')).toEqual(['x', 'd', 'y'])
    expect(nextOrder(['x', 'y'], 'd', null)).toEqual(['x', 'y', 'd'])
  })
  it('falls back to append on an unknown beforeId or empty group', () => {
    expect(nextOrder(['a', 'b'], 'c', 'z')).toEqual(['a', 'b', 'c'])
    expect(nextOrder([], 'd', null)).toEqual(['d'])
  })
})

describe('setContainerOf — the container a dragged Set resolves into', () => {
  const idx = buildIndex(tree)
  const get = (k: string): Entry => {
    const e = idx.byId.get(k)
    if (!e) throw new Error(`no entry ${k}`)
    return e
  }
  it('resolves a container header to itself, a hovered Set to its parent, a page to its parent container', () => {
    expect(setContainerOf(get('c1'), idx)?.path).toBe('Col') // the Collection itself
    expect(setContainerOf(get('s1'), idx)?.path).toBe('Col') // a depth-1 Set → its parent Collection
    expect(setContainerOf(get('s2'), idx)?.path).toBe('Col/Set') // a Sub-Set → its parent Set
    expect(setContainerOf(get('p3'), idx)?.path).toBe('Col') // a Collection-loose page → the Collection
    expect(setContainerOf(get('p1'), idx)?.path).toBe('Col/Set') // a page in a Set → that Set
  })
  it('returns null for a context row (a Set may not live there)', () => {
    expect(setContainerOf(get('a1'), idx)).toBeNull()
  })
})

describe('isSelfOrDescendant — cycle guard for Set reparenting', () => {
  const idx = buildIndex(tree)
  it('flags a target that is the dragged Set itself or one of its descendants', () => {
    expect(isSelfOrDescendant('s1', 's1', idx)).toBe(true) // self
    expect(isSelfOrDescendant('s2', 's1', idx)).toBe(true) // s2 is a descendant of s1
  })
  it('allows an unrelated target', () => {
    expect(isSelfOrDescendant('c1', 's1', idx)).toBe(false) // the Collection is an ancestor, not a descendant
    expect(isSelfOrDescendant('s1', 's2', idx)).toBe(false) // s1 is not under s2
  })
})

describe('slotInGroup — insertion slot over a same-group sibling', () => {
  const row = (id: string, top: number): MeasuredRow => ({ id, top, bottom: top + 20, mid: top + 10 })
  it('drops before the hovered row when the pointer is in its top half', () => {
    expect(slotInGroup(['a', 'b', 'c'], row('b', 100), 105, 'x')).toEqual({ beforeId: 'b', edge: 100 })
  })
  it('drops after the hovered row (before the next) when in its bottom half', () => {
    expect(slotInGroup(['a', 'b', 'c'], row('b', 100), 115, 'x')).toEqual({ beforeId: 'c', edge: 120 })
  })
  it('appends (null) when "after" would resolve to the dragged item itself', () => {
    expect(slotInGroup(['a', 'b', 'c'], row('b', 100), 115, 'c')).toEqual({ beforeId: null, edge: 120 })
  })
})
