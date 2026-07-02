import { describe, it, expect } from 'vitest'
import type { ResolvedGroup } from '@shared/types'
import type { MeasuredRow } from '@renderer/Sidebar/sidebarDndModel'
import {
  allStructuralIds,
  bandSlot,
  canNest,
  flattenBands,
  propertyOrderAfterDrop,
  reparentFsOrder,
  structuralOrderAfterDrop
} from './bandDndModel'

const sg = (key: string, children?: ResolvedGroup[]): ResolvedGroup => ({
  key,
  kind: 'structural-set',
  items: [],
  ...(children ? { children } : {}),
  isCollapsed: false
})
const prop = (key: string): ResolvedGroup => ({ key, kind: 'property', items: [], isCollapsed: false })
const ungrouped: ResolvedGroup = { key: '_ungrouped', kind: 'ungrouped', items: [], isCollapsed: false }

// A[A1, A2], B[B1] + a loose tail — the plan's 2-level fixture.
const tree = [sg('A', [sg('A1'), sg('A2')]), sg('B', [sg('B1')]), ungrouped]

/** Stack measured rows (height 24) in the given display order. */
const measure = (ids: string[]): MeasuredRow[] =>
  ids.map((id, i) => ({ id, top: i * 24, bottom: i * 24 + 24, mid: i * 24 + 12 }))

describe('flattenBands', () => {
  it('lists visible band headers in display order with depth + parent, excluding ungrouped', () => {
    expect(flattenBands(tree, new Set())).toEqual([
      { id: 'A', kind: 'set', depth: 0, parentId: null },
      { id: 'A1', kind: 'set', depth: 1, parentId: 'A' },
      { id: 'A2', kind: 'set', depth: 1, parentId: 'A' },
      { id: 'B', kind: 'set', depth: 0, parentId: null },
      { id: 'B1', kind: 'set', depth: 1, parentId: 'B' }
    ])
  })

  it('respects the LIVE collapsed set — a collapsed subtree keeps its header, drops its children', () => {
    expect(flattenBands(tree, new Set(['A'])).map((b) => b.id)).toEqual(['A', 'B', 'B1'])
  })

  it('includes property bands and excludes the ungrouped tail', () => {
    expect(flattenBands([prop('open'), prop('done'), ungrouped], new Set())).toEqual([
      { id: 'open', kind: 'property', depth: 0, parentId: null },
      { id: 'done', kind: 'property', depth: 0, parentId: null }
    ])
  })
})

describe('allStructuralIds', () => {
  it('returns the FULL tree id set in tree order, collapsed subtrees included, never ungrouped', () => {
    expect(allStructuralIds(tree)).toEqual(['A', 'A1', 'A2', 'B', 'B1'])
  })
})

describe('bandSlot', () => {
  const bands = flattenBands(tree, new Set())
  const rows = measure(['A', 'A1', 'A2', 'B', 'B1'])

  it('HIGH-1 regression: the slot above A from A1 implies parent ROOT — a parent change, not a reorder', () => {
    const slot = bandSlot(bands, rows, 2, 'A1')
    expect(slot).toEqual({ beforeId: 'A', impliedParentId: null, nestInto: null, lineY: 0 })
  })

  it('resolves the slot under an expanded header as first-child of that set', () => {
    // Bottom zone of A (y=23) → before A1, inside A.
    const slot = bandSlot(bands, rows, 23, 'B')
    expect(slot).toMatchObject({ beforeId: 'A1', impliedParentId: 'A' })
  })

  it('nests into a set band via its middle zone', () => {
    // B spans 72–96; its middle zone is the nest target.
    const slot = bandSlot(bands, rows, 84, 'A1')
    expect(slot).toMatchObject({ beforeId: null, impliedParentId: 'B', nestInto: 'B' })
  })

  it('never nests into the dragged band or its descendants — middle falls back to the half split', () => {
    // Middle of A1 while dragging A: nest is illegal (descendant); bottom half → the next slot
    // outside A's subtree (before B at root).
    const slot = bandSlot(bands, rows, 38, 'A')
    expect(slot?.nestInto).toBeNull()
    expect(slot).toMatchObject({ beforeId: 'B', impliedParentId: null })
  })

  it('refuses a slot whose implied parent sits inside the dragged subtree', () => {
    // Top zone of A2 while dragging A implies parent A — illegal, and the skip walks past the
    // subtree to a root slot instead of returning it.
    const slot = bandSlot(bands, rows, 50, 'A')
    expect(slot?.impliedParentId ?? null).not.toBe('A')
  })

  it('drops below the last band as a root append', () => {
    expect(bandSlot(bands, rows, 400, 'A1')).toEqual({
      beforeId: null,
      impliedParentId: null,
      nestInto: null,
      lineY: 120
    })
  })

  it('splits property bands in half and never nests them', () => {
    const pBands = flattenBands([prop('open'), prop('done'), ungrouped], new Set())
    const pRows = measure(['open', 'done'])
    expect(bandSlot(pBands, pRows, 34, 'open')).toMatchObject({ beforeId: 'done', nestInto: null })
    expect(bandSlot(pBands, pRows, 40, 'open')).toMatchObject({ beforeId: null, nestInto: null })
  })

  it('hit-tests only visible bands when a subtree is collapsed', () => {
    const cBands = flattenBands(tree, new Set(['A']))
    const cRows = measure(['A', 'B', 'B1'])
    // Bottom zone of collapsed A (y=23) → before B at root, never inside the hidden subtree.
    expect(bandSlot(cBands, cRows, 23, 'B1')).toMatchObject({ beforeId: 'B', impliedParentId: null })
  })
})

describe('canNest', () => {
  const bands = flattenBands(tree, new Set())

  it('blocks self and descendants, allows a legal set target', () => {
    expect(canNest('A', 'A', bands)).toBe(false)
    expect(canNest('A', 'A1', bands)).toBe(false)
    expect(canNest('A', 'B', bands)).toBe(true)
    expect(canNest('A1', 'B1', bands)).toBe(true)
  })

  it('never nests into a property band', () => {
    const pBands = flattenBands([prop('open')], new Set())
    expect(canNest('x', 'open', pBands)).toBe(false)
  })
})

describe('structuralOrderAfterDrop', () => {
  const fullIds = ['A', 'A1', 'A2', 'B', 'B1']

  it('HIGH-2 regression: collapsed-sibling ids survive the merge — dragging B above A keeps A2/A1', () => {
    expect(structuralOrderAfterDrop(['A', 'A2', 'A1', 'B'], fullIds, 'B', 'A')).toEqual([
      'B',
      'A',
      'A2',
      'A1',
      'B1'
    ])
  })

  it('seeds from the full tree in tree order when no prior order exists', () => {
    expect(structuralOrderAfterDrop([], fullIds, 'B', 'A')).toEqual(['B', 'A', 'A1', 'A2', 'B1'])
  })

  it('appends on a null beforeId and prunes ids that left the tree', () => {
    expect(structuralOrderAfterDrop(['gone', 'B', 'A'], fullIds, 'A', null)).toEqual([
      'B',
      'A1',
      'A2',
      'B1',
      'A'
    ])
  })
})

describe('propertyOrderAfterDrop', () => {
  it('moves the dragged key before the target within the present keys', () => {
    expect(propertyOrderAfterDrop(['open', 'active', 'done'], 'done', 'open')).toEqual([
      'done',
      'open',
      'active'
    ])
    expect(propertyOrderAfterDrop(['open', 'active', 'done'], 'open', null)).toEqual([
      'active',
      'done',
      'open'
    ])
  })
})

describe('reparentFsOrder', () => {
  it('APPENDS the moved id regardless of the visual drop slot (C-4 order-leak guard)', () => {
    expect(reparentFsOrder(['x', 'y'], 'm')).toEqual(['x', 'y', 'm'])
    expect(reparentFsOrder([], 'm')).toEqual(['m'])
    // Already present (same-parent safety): moves to the tail, never duplicates.
    expect(reparentFsOrder(['m', 'x'], 'm')).toEqual(['x', 'm'])
  })
})
