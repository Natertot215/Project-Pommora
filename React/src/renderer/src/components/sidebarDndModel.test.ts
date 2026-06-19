import { describe, it, expect } from 'vitest'
import { buildIndex, nextOrder, collectionOf, slotInGroup, type Entry, type MeasuredRow } from './sidebarDndModel'
import type { AreaNode, NexusTree, PageTypeNode } from '@shared/types'

// 1 vault → (1 collection → 1 set [P1, P2] + loose P3) + loose P4, plus two Areas (contexts).
const vaults: PageTypeNode[] = [
  {
    id: 'v1',
    kind: 'pageType',
    title: 'Vault',
    path: 'Vault',
    pages: [{ id: 'p4', kind: 'page', title: 'P4', path: 'Vault/P4.md' }],
    collections: [
      {
        id: 'c1',
        kind: 'collection',
        title: 'Col',
        path: 'Vault/Col',
        pages: [{ id: 'p3', kind: 'page', title: 'P3', path: 'Vault/Col/P3.md' }],
        sets: [
          {
            id: 's1',
            kind: 'set',
            title: 'Set',
            path: 'Vault/Col/Set',
            selectable: false,
            pages: [
              { id: 'p1', kind: 'page', title: 'P1', path: 'Vault/Col/Set/P1.md' },
              { id: 'p2', kind: 'page', title: 'P2', path: 'Vault/Col/Set/P2.md' }
            ]
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
const tree = { vaults, userSections: [], contexts: { areas, topics: [], projects: [] } } as unknown as NexusTree

describe('buildIndex', () => {
  const idx = buildIndex(tree)
  it('indexes containers with child page ids, child container ids + render depth', () => {
    expect(idx.byId.get('v1')).toMatchObject({ kind: 'vault', depth: 0, pageIds: ['p4'], containerIds: ['c1'] })
    expect(idx.byId.get('c1')).toMatchObject({ kind: 'collection', depth: 1, pageIds: ['p3'], containerIds: ['s1'] })
    expect(idx.byId.get('s1')).toMatchObject({ kind: 'set', depth: 2, pageIds: ['p1', 'p2'], containerIds: [] })
  })
  it('indexes pages with their parent container + render depth', () => {
    expect(idx.byId.get('p1')).toMatchObject({ kind: 'page', depth: 3, parentId: 's1', parentPath: 'Vault/Col/Set' })
    expect(idx.byId.get('p3')).toMatchObject({ kind: 'page', depth: 2, parentId: 'c1', parentPath: 'Vault/Col' })
    expect(idx.byId.get('p4')).toMatchObject({ kind: 'page', depth: 1, parentId: 'v1', parentPath: 'Vault' })
  })
  it('exposes top-level groups + indexes contexts as depth-1 leaves (nested under their tier)', () => {
    expect(idx.vaultIds).toEqual(['v1'])
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

describe('collectionOf — the collection a dragged set resolves into', () => {
  const idx = buildIndex(tree)
  const get = (k: string): Entry => {
    const e = idx.byId.get(k)
    if (!e) throw new Error(`no entry ${k}`)
    return e
  }
  it('resolves a collection / a set / a page down to its collection', () => {
    expect(collectionOf(get('c1'), idx)?.path).toBe('Vault/Col') // the collection itself
    expect(collectionOf(get('s1'), idx)?.path).toBe('Vault/Col') // a set → its parent collection
    expect(collectionOf(get('p3'), idx)?.path).toBe('Vault/Col') // a page in the collection
    expect(collectionOf(get('p1'), idx)?.path).toBe('Vault/Col') // a page in a set → set's collection
  })
  it('returns null for rows not inside a collection (vault-root page, vault, context)', () => {
    expect(collectionOf(get('p4'), idx)).toBeNull() // a page sitting at vault root
    expect(collectionOf(get('v1'), idx)).toBeNull() // a vault
    expect(collectionOf(get('a1'), idx)).toBeNull() // a context (area)
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
