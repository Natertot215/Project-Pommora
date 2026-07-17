import { describe, expect, it } from 'vitest'
import type { MeasuredRow } from '@renderer/Sidebar/sidebarDndModel'
import { RESERVED_PROPERTY_ID, type PropertyDefinition } from '@shared/properties'
import type { SavedView } from '@shared/views'
import type { PaneRow } from './paneDndModel'
import { hiddenListIds, hiddenPaneSlot, hideShown, placeInShown, unhide } from './hiddenPaneModel'

const { title, tier1, tier3, modifiedAt } = RESERVED_PROPERTY_ID

const def = (id: string): PropertyDefinition => ({ id, name: id, type: 'select' })

const view = (property_order: string[], hidden_properties: string[]): SavedView => ({
  id: 'view_1',
  name: 'Table',
  type: 'table',
  property_order,
  hidden_properties,
})

describe('hiddenListIds', () => {
  it('orders by the COLLECTION schema, not the hidden array', () => {
    const schema = [def('a'), def('b'), def('c')]
    expect(hiddenListIds(['c', 'a'], schema)).toEqual(['a', 'c'])
  })

  it('lists hidden tiers first (fixed order), then props, trails Modified, drops stale ids', () => {
    const schema = [def('a')]
    expect(hiddenListIds([tier1, modifiedAt, 'stale', 'a'], schema)).toEqual([
      tier1,
      'a',
      modifiedAt,
    ])
  })
})

describe('placeInShown', () => {
  it('reorders a shown row, writing the full visible order verbatim with hidden ids trailing', () => {
    const v = view([title, 'a', 'b', 'h', 'c'], ['h'])
    expect(placeInShown(v, [title, 'a', 'b', 'c'], ['a', 'b', 'c'], 'c', 0)).toEqual({
      property_order: [title, 'c', 'a', 'b', 'h'],
      hidden_properties: ['h'],
    })
  })

  it('anchors the section slot inside the full order — Title and tiers hold their places', () => {
    const v = view([title, 'a', tier3, 'b'], [])
    expect(placeInShown(v, [title, 'a', tier3, 'b'], ['a', 'b'], 'b', 0).property_order).toEqual([
      title,
      'b',
      'a',
      tier3,
    ])
  })

  it('unhides a dragged-in row at the slot and lifts its flag', () => {
    const v = view([title, 'a', 'b', 'h'], ['h'])
    expect(placeInShown(v, [title, 'a', 'b'], ['a', 'b'], 'h', 1)).toEqual({
      property_order: [title, 'a', 'h', 'b'],
      hidden_properties: [],
    })
  })

  it('appends past the last section row, before nothing — a hidden id never in property_order lands', () => {
    const v = view(['a'], ['h'])
    expect(placeInShown(v, ['a'], ['a'], 'h', 1)).toEqual({
      property_order: ['a', 'h'],
      hidden_properties: [],
    })
  })

  it('preserves foreign property_order ids at the tail', () => {
    const v = view(['a', 'future_key', 'b'], [])
    expect(placeInShown(v, ['a', 'b'], ['a', 'b'], 'b', 0).property_order).toEqual([
      'b',
      'a',
      'future_key',
    ])
  })
})

describe('hideShown / unhide', () => {
  it('hide appends the flag once and never touches property_order', () => {
    const v = view(['a', 'b'], [])
    expect(hideShown(v, 'a')).toEqual({ hidden_properties: ['a'] })
    expect(hideShown(view(['a'], ['a']), 'a')).toEqual({ hidden_properties: ['a'] })
  })

  it('unhide lifts only the toggled flag', () => {
    expect(unhide(view([], ['a', 'b']), 'a')).toEqual({ hidden_properties: ['b'] })
  })
})

describe('hiddenPaneSlot', () => {
  const rows: MeasuredRow[] = [
    { id: 'a', top: 0, bottom: 20, mid: 10 },
    { id: 'b', top: 20, bottom: 40, mid: 30 },
    { id: 'h', top: 60, bottom: 80, mid: 70 },
  ]
  const byId = new Map<string, PaneRow>([
    ['a', { id: 'a', group: 'assigned' }],
    ['b', { id: 'b', group: 'assigned' }],
    ['h', { id: 'h', group: 'all' }],
  ])
  const regions = { assigned: { top: 0, bottom: 50 }, all: { top: 50, bottom: 100 } }

  it('reorders a shown row within the properties region', () => {
    expect(hiddenPaneSlot(rows, byId, regions, 35, 'a')?.drop).toEqual({
      kind: 'reorder-assigned',
      propId: 'a',
      toIndex: 1,
    })
  })

  it('unhides a hidden row dragged into the properties region', () => {
    expect(hiddenPaneSlot(rows, byId, regions, 5, 'h')?.drop).toEqual({
      kind: 'assign',
      propId: 'h',
      toIndex: 0,
    })
  })

  it('hides a shown row dropped in the hidden zone — membership drop: highlight, no line', () => {
    const slot = hiddenPaneSlot(rows, byId, regions, 70, 'a')
    expect(slot?.drop).toEqual({ kind: 'unassign', propId: 'a' })
    expect(slot?.lineY).toBeNull()
    expect(slot?.highlightAll).toBe(true)
  })

  it('keeps a hidden row inert over its own zone — no reorder within hidden', () => {
    expect(hiddenPaneSlot(rows, byId, regions, 70, 'h')).toBeNull()
  })

  it('never hides Title — a drop into the hidden zone is a no-op', () => {
    const withTitle = new Map(byId).set(title, { id: title, group: 'assigned' })
    expect(hiddenPaneSlot(rows, withTitle, regions, 70, title)).toBeNull()
  })

  it('is inert above and below the pane regions', () => {
    expect(hiddenPaneSlot(rows, byId, regions, -10, 'a')).toBeNull()
    expect(hiddenPaneSlot(rows, byId, regions, 150, 'a')).toBeNull()
  })

  it('never highlights during a positional drop in the shown zone', () => {
    expect(hiddenPaneSlot(rows, byId, regions, 35, 'h')?.highlightAll).toBe(false)
  })
})
