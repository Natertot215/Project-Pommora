import { describe, it, expect } from 'vitest'
import type { CollectionNode, PageNode, SetNode, ViewRow } from '@shared/types'
import type { GroupConfig } from '@shared/views'
import type { PageFrontmatter } from '@shared/schemas'
import type { PropertyDefinition } from '@shared/properties'
import { dateBucketKey, flattenContainer, resolveGroups } from './group'

// ---- builders ----
const page = (id: string): PageNode => ({ kind: 'page', id, title: id, path: `${id}.md` })
const set = (id: string, pages: PageNode[] = [], sets: SetNode[] = []): SetNode => ({
  kind: 'set',
  id,
  title: id,
  path: id,
  pages,
  sets
})
const collection = (sets: SetNode[] = [], pages: PageNode[] = []): CollectionNode => ({
  kind: 'collection',
  id: 'col',
  title: 'Col',
  path: 'Col',
  sets,
  pages
})
const keys = (groups: { key: string }[]): string[] => groups.map((g) => g.key)
const itemIds = (g: { items: ViewRow[] }): string[] => g.items.map((r) => r.id)

const statusSchema: PropertyDefinition[] = [
  {
    id: 'prop_status',
    name: 'Status',
    type: 'status',
    status_groups: [
      {
        id: 'upcoming',
        label: 'U',
        color: 'gray',
        options: [
          { value: 'not_started', label: 'Not started', group_id: 'upcoming' },
          { value: 'opt_open', label: 'Open', group_id: 'upcoming' }
        ]
      },
      { id: 'in_progress', label: 'IP', color: 'blue', options: [{ value: 'in_progress', label: 'Active', group_id: 'in_progress' }] },
      { id: 'done', label: 'D', color: 'green', options: [{ value: 'done', label: 'Done', group_id: 'done' }] }
    ]
  }
]

describe('flattenContainer + structural grouping', () => {
  it('groups a Collection by its Sets, nests Sub-Sets, roots loose pages in a trailing band', () => {
    const sub = set('sub', [page('p_sub')])
    const setA = set('setA', [page('p_a')], [sub])
    const setB = set('setB', [page('p_b')])
    const col = collection([setA, setB], [page('p_root')])
    const { rows, setTree } = flattenContainer(col, {})
    const groups = resolveGroups(rows, { kind: 'structural' }, [], setTree, null)

    expect(groups.map((g) => [g.key, g.kind])).toEqual([
      ['setA', 'structural-set'],
      ['setB', 'structural-set'],
      ['_ungrouped', 'ungrouped']
    ])
    expect(itemIds(groups[0])).toEqual(['p_a'])
    expect(keys(groups[0].children ?? [])).toEqual(['sub'])
    expect(itemIds(groups[0].children![0])).toEqual(['p_sub'])
    expect(itemIds(groups[2])).toEqual(['p_root'])
  })

  it('groups a Set container identically — Sub-Sets become top groups, own pages band (shared path)', () => {
    const container = set('setC', [page('p_own')], [set('subX', [page('p_x')]), set('subY', [page('p_y')])])
    const { rows, setTree } = flattenContainer(container, {})
    const groups = resolveGroups(rows, { kind: 'structural' }, [], setTree, null)
    expect(keys(groups)).toEqual(['subX', 'subY', '_ungrouped'])
    expect(itemIds(groups[2])).toEqual(['p_own'])
  })

  it('still shows an empty Set as a disclosure group', () => {
    const { rows, setTree } = flattenContainer(collection([set('empty', [])], []), {})
    const groups = resolveGroups(rows, { kind: 'structural' }, [], setTree, null)
    expect(keys(groups)).toEqual(['empty'])
    expect(groups[0].items).toEqual([])
  })

  it('with zero Sets yields a single headerless band, and nothing for an empty container', () => {
    const { rows, setTree } = flattenContainer(collection([], [page('p1'), page('p2')]), {})
    const groups = resolveGroups(rows, { kind: 'structural' }, [], setTree, null)
    expect(keys(groups)).toEqual(['_ungrouped'])
    expect(groups[0].kind).toBe('ungrouped')
    expect(itemIds(groups[0])).toEqual(['p1', 'p2'])
    expect(resolveGroups([], { kind: 'structural' }, [], [], null)).toEqual([])
  })

  it('applies the sorter within each group', () => {
    const { rows, setTree } = flattenContainer(collection([], [page('b'), page('a'), page('c')]), {})
    const byId = (r: ViewRow[]): ViewRow[] => [...r].sort((x, y) => (x.id < y.id ? -1 : 1))
    const groups = resolveGroups(rows, { kind: 'flat' }, [], setTree, byId)
    expect(itemIds(groups[0])).toEqual(['a', 'b', 'c'])
  })

  it('marks groups collapsed from the collapsed set', () => {
    const { rows, setTree } = flattenContainer(collection([set('s1', [page('p1')])], []), {})
    const groups = resolveGroups(rows, { kind: 'structural' }, [], setTree, null, ['s1'])
    expect(groups[0].isCollapsed).toBe(true)
  })
})

describe('flat grouping', () => {
  it('drops set structure into one band of all rows', () => {
    const { rows, setTree } = flattenContainer(collection([set('s1', [page('p1')])], [page('p2')]), {})
    const groups = resolveGroups(rows, { kind: 'flat' }, [], setTree, null)
    expect(keys(groups)).toEqual(['_ungrouped'])
    expect(itemIds(groups[0]).sort()).toEqual(['p1', 'p2'])
  })
})

describe('property grouping — status manual order', () => {
  const values: Record<string, PageFrontmatter> = {
    p1: { id: 'p1', properties: { prop_status: { $status: 'done' } } },
    p2: { id: 'p2', properties: { prop_status: { $status: 'in_progress' } } },
    p3: { id: 'p3', properties: { prop_status: { $status: 'not_started' } } },
    p4: { id: 'p4', properties: {} }
  }
  const col = collection([], [page('p1'), page('p2'), page('p3'), page('p4')])
  const base: GroupConfig = {
    kind: 'property',
    property_id: 'prop_status',
    order_mode: 'manual',
    order: ['in_progress', 'opt_open', 'not_started', 'done'],
    empty_placement: 'bottom',
    hide_empty_groups: false
  }

  it('orders buckets by manual order, drops empty buckets, no-value band at bottom', () => {
    const { rows, setTree } = flattenContainer(col, values)
    const groups = resolveGroups(rows, base, statusSchema, setTree, null)
    expect(keys(groups)).toEqual(['in_progress', 'not_started', 'done', '_ungrouped'])
  })

  it('places the no-value band at top when empty_placement is top', () => {
    const { rows, setTree } = flattenContainer(col, values)
    const groups = resolveGroups(rows, { ...base, empty_placement: 'top' }, statusSchema, setTree, null)
    expect(keys(groups)).toEqual(['_ungrouped', 'in_progress', 'not_started', 'done'])
  })

  it('drops the no-value band when hide_empty_groups is set', () => {
    const { rows, setTree } = flattenContainer(col, values)
    const groups = resolveGroups(rows, { ...base, hide_empty_groups: true }, statusSchema, setTree, null)
    expect(keys(groups)).toEqual(['in_progress', 'not_started', 'done'])
  })
})

describe('property grouping — configured / reversed / checkbox / date', () => {
  const selSchema: PropertyDefinition[] = [
    {
      id: 'prop_sel',
      name: 'Sel',
      type: 'select',
      select_options: [
        { value: 'a', label: 'A' },
        { value: 'b', label: 'B' },
        { value: 'c', label: 'C' }
      ]
    }
  ]
  const cfg = (over: Partial<Extract<GroupConfig, { kind: 'property' }>>): GroupConfig => ({
    kind: 'property',
    property_id: 'prop_sel',
    order_mode: 'configured',
    empty_placement: 'bottom',
    hide_empty_groups: false,
    ...over
  })

  it('configured uses schema option order; reversed flips it', () => {
    const values = {
      p1: { id: 'p1', properties: { prop_sel: 'c' } },
      p2: { id: 'p2', properties: { prop_sel: 'a' } },
      p3: { id: 'p3', properties: { prop_sel: 'b' } }
    }
    const { rows, setTree } = flattenContainer(collection([], [page('p1'), page('p2'), page('p3')]), values)
    expect(keys(resolveGroups(rows, cfg({ order_mode: 'configured' }), selSchema, setTree, null))).toEqual(['a', 'b', 'c'])
    expect(keys(resolveGroups(rows, cfg({ order_mode: 'reversed' }), selSchema, setTree, null))).toEqual(['c', 'b', 'a'])
  })

  it('routes a nil checkbox to the false bucket with no no-value band', () => {
    const cbSchema: PropertyDefinition[] = [{ id: 'prop_done', name: 'Done', type: 'checkbox' }]
    const values = {
      p1: { id: 'p1', properties: { prop_done: true } },
      p2: { id: 'p2', properties: { prop_done: false } },
      p3: { id: 'p3', properties: {} }
    }
    const { rows, setTree } = flattenContainer(collection([], [page('p1'), page('p2'), page('p3')]), values)
    const groups = resolveGroups(
      rows,
      { kind: 'property', property_id: 'prop_done', order_mode: 'configured', empty_placement: 'bottom', hide_empty_groups: false },
      cbSchema,
      setTree,
      null
    )
    expect(keys(groups)).toEqual(['false', 'true'])
    expect(itemIds(groups[0])).toEqual(['p2', 'p3'])
    expect(itemIds(groups[1])).toEqual(['p1'])
  })

  it('buckets dates by granularity (same month together)', () => {
    const dateSchema: PropertyDefinition[] = [{ id: 'prop_when', name: 'When', type: 'datetime' }]
    const values = {
      p1: { id: 'p1', properties: { prop_when: '2026-06-10T12:00:00Z' } },
      p2: { id: 'p2', properties: { prop_when: '2026-06-25T12:00:00Z' } },
      p3: { id: 'p3', properties: { prop_when: '2026-07-15T12:00:00Z' } }
    }
    const { rows, setTree } = flattenContainer(collection([], [page('p1'), page('p2'), page('p3')]), values)
    const groups = resolveGroups(
      rows,
      { kind: 'property', property_id: 'prop_when', order_mode: 'configured', date_granularity: 'month', empty_placement: 'bottom', hide_empty_groups: false },
      dateSchema,
      setTree,
      null
    )
    expect(keys(groups)).toEqual(['2026-06', '2026-07'])
    expect(itemIds(groups[0]).sort()).toEqual(['p1', 'p2'])
  })
})

describe('property grouping — non-groupable fallback', () => {
  it('falls back to structural for number and multi_select group properties', () => {
    const { rows, setTree } = flattenContainer(collection([set('s1', [page('p1')])], [page('p2')]), {})
    const numGroups = resolveGroups(
      rows,
      { kind: 'property', property_id: 'prop_num', order_mode: 'configured', empty_placement: 'bottom', hide_empty_groups: false },
      [{ id: 'prop_num', name: 'Num', type: 'number' }],
      setTree,
      null
    )
    expect(keys(numGroups)).toEqual(['s1', '_ungrouped'])

    const msGroups = resolveGroups(
      rows,
      { kind: 'property', property_id: 'prop_tags', order_mode: 'configured', empty_placement: 'bottom', hide_empty_groups: false },
      [{ id: 'prop_tags', name: 'Tags', type: 'multi_select' }],
      setTree,
      null
    )
    expect(keys(msGroups)).toEqual(['s1', '_ungrouped'])
  })
})

describe('dateBucketKey', () => {
  it('formats month and year keys (zero-padded, lexicographically chronological)', () => {
    expect(dateBucketKey('2026-06-15T12:00:00Z', 'month')).toBe('2026-06')
    expect(dateBucketKey('2026-06-15T12:00:00Z', 'year')).toBe('2026')
  })

  it('formats day and week keys with the right shape', () => {
    expect(dateBucketKey('2026-06-15T12:00:00Z', 'day')).toMatch(/^\d{4}-\d{2}-\d{2}$/)
    expect(dateBucketKey('2026-06-15T12:00:00Z', 'week')).toMatch(/^\d{4}-W\d{2}$/)
  })

  it('returns null for an unparseable date', () => {
    expect(dateBucketKey('not-a-date', 'month')).toBeNull()
  })
})
