import { describe, it, expect } from 'vitest'
import type { ViewRow } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { makeSorter, resolvedSortCount } from './sort'

const schema: PropertyDefinition[] = [
  {
    id: 'prop_sel',
    name: 'Sel',
    type: 'select',
    select_options: [
      { value: 'a', label: 'A' },
      { value: 'b', label: 'B' },
      { value: 'c', label: 'C' }
    ]
  },
  {
    id: 'prop_status',
    name: 'Status',
    type: 'status',
    status_groups: [
      { id: 'upcoming', label: 'U', color: 'gray', options: [{ value: 'not_started', label: 'NS', group_id: 'upcoming' }] },
      { id: 'in_progress', label: 'IP', color: 'blue', options: [{ value: 'in_progress', label: 'Active', group_id: 'in_progress' }] },
      { id: 'done', label: 'D', color: 'green', options: [{ value: 'done', label: 'Done', group_id: 'done' }] }
    ]
  },
  { id: 'prop_num', name: 'Num', type: 'number' },
  { id: 'prop_done', name: 'Done', type: 'checkbox' },
  { id: 'prop_when', name: 'When', type: 'datetime' },
  { id: 'prop_led', name: 'Edited', type: 'last_edited_time' },
  { id: 'prop_rel', name: 'Rel', type: 'context', context_target: { kind: 'context_tier', tier: 1 } },
  { id: 'prop_link', name: 'Link', type: 'url' }
]

function makeRow(
  id: string,
  opts: { title?: string; props?: Record<string, unknown>; modified_at?: string; created_at?: string } = {}
): ViewRow {
  return {
    id,
    title: opts.title ?? id,
    path: `${id}.md`,
    frontmatter: {
      id,
      ...(opts.modified_at ? { modified_at: opts.modified_at } : {}),
      ...(opts.created_at ? { created_at: opts.created_at } : {}),
      properties: opts.props ?? {}
    }
  }
}

const ids = (rows: ViewRow[]): string[] => rows.map((r) => r.id)

describe('makeSorter — type-aware single criterion', () => {
  it('url sorts by the SHOWN text (alias, else URL), not the raw [alias](url) (build-breaker #3)', () => {
    const rows = [
      makeRow('r_zebra', { props: { prop_link: '[Zebra](https://a.co)' } }),
      makeRow('r_apple', { props: { prop_link: '[Apple](https://z.co)' } }),
      makeRow('r_bare', { props: { prop_link: 'https://m.co' } })
    ]
    const sorter = makeSorter([{ property_id: 'prop_link', direction: 'ascending' }], schema)
    // Apple < https://m.co < Zebra by display — not clumped by the leading `[` of the two aliases.
    expect(ids(sorter?.(rows) ?? rows)).toEqual(['r_apple', 'r_bare', 'r_zebra'])
  })

  it('select sorts by schema option order, unknown values last', () => {
    const rows = [
      makeRow('r1', { props: { prop_sel: 'c' } }),
      makeRow('r2', { props: { prop_sel: 'a' } }),
      makeRow('r3', { props: { prop_sel: 'zzz' } }),
      makeRow('r4', { props: { prop_sel: 'b' } })
    ]
    const sorter = makeSorter([{ property_id: 'prop_sel', direction: 'ascending' }], schema)!
    expect(ids(sorter(rows))).toEqual(['r2', 'r4', 'r1', 'r3'])
  })

  it('status sorts by flattened group-option order, and descending flips', () => {
    const rows = [
      makeRow('r1', { props: { prop_status: { $status: 'done' } } }),
      makeRow('r2', { props: { prop_status: { $status: 'not_started' } } }),
      makeRow('r3', { props: { prop_status: { $status: 'in_progress' } } })
    ]
    expect(ids(makeSorter([{ property_id: 'prop_status', direction: 'ascending' }], schema)!(rows))).toEqual([
      'r2',
      'r3',
      'r1'
    ])
    expect(ids(makeSorter([{ property_id: 'prop_status', direction: 'descending' }], schema)!(rows))).toEqual([
      'r1',
      'r3',
      'r2'
    ])
  })

  it('number sorts numerically, absent first ascending', () => {
    const rows = [
      makeRow('r1', { props: { prop_num: 5 } }),
      makeRow('r2', { props: { prop_num: 2 } }),
      makeRow('r3', { props: {} })
    ]
    expect(ids(makeSorter([{ property_id: 'prop_num', direction: 'ascending' }], schema)!(rows))).toEqual([
      'r3',
      'r2',
      'r1'
    ])
  })

  it('checkbox sorts false before true (absent = false)', () => {
    const rows = [
      makeRow('r1', { props: { prop_done: true } }),
      makeRow('r2', { props: { prop_done: false } }),
      makeRow('r3', { props: {} })
    ]
    expect(ids(makeSorter([{ property_id: 'prop_done', direction: 'ascending' }], schema)!(rows))).toEqual([
      'r2',
      'r3',
      'r1'
    ])
  })

  it('date sorts chronologically, absent earliest', () => {
    const rows = [
      makeRow('r1', { props: { prop_when: '2026-06-20T10:00:00Z' } }),
      makeRow('r2', { props: { prop_when: '2026-06-15T10:00:00Z' } }),
      makeRow('r3', { props: {} })
    ]
    expect(ids(makeSorter([{ property_id: 'prop_when', direction: 'ascending' }], schema)!(rows))).toEqual([
      'r3',
      'r2',
      'r1'
    ])
  })

  it('last_edited_time sorts by date (routes to the date branch)', () => {
    const rows = [
      makeRow('r1', { props: { prop_led: '2026-06-20T10:00:00Z' } }),
      makeRow('r2', { props: { prop_led: '2026-06-15T10:00:00Z' } })
    ]
    expect(ids(makeSorter([{ property_id: 'prop_led', direction: 'ascending' }], schema)!(rows))).toEqual([
      'r2',
      'r1'
    ])
  })

  it('relation extracts to "" — a usable but no-op sorter that holds input order', () => {
    const rows = [
      makeRow('r1', { props: { prop_rel: [{ $ctx: 'z' }] } }),
      makeRow('r2', { props: { prop_rel: [{ $ctx: 'a' }] } })
    ]
    const sorter = makeSorter([{ property_id: 'prop_rel', direction: 'ascending' }], schema)
    expect(sorter).not.toBeNull()
    expect(ids(sorter!(rows))).toEqual(['r1', 'r2'])
  })
})

describe('makeSorter — reserved presets', () => {
  it('_title compares case-insensitively', () => {
    const rows = [makeRow('r1', { title: 'banana' }), makeRow('r2', { title: 'Apple' }), makeRow('r3', { title: 'cherry' })]
    expect(ids(makeSorter([{ property_id: '_title', direction: 'ascending' }], schema)!(rows))).toEqual([
      'r2',
      'r1',
      'r3'
    ])
  })

  it('_id compares lexicographically (ULID = creation order)', () => {
    const rows = [makeRow('01C'), makeRow('01A'), makeRow('01B')]
    expect(ids(makeSorter([{ property_id: '_id', direction: 'ascending' }], schema)!(rows))).toEqual([
      '01A',
      '01B',
      '01C'
    ])
  })

  it('_modified_at uses created_at as a fallback when modified_at is absent', () => {
    const rows = [
      makeRow('r1', { modified_at: '2026-06-20T10:00:00Z' }),
      makeRow('r2', { created_at: '2026-06-15T10:00:00Z' }),
      makeRow('r3', { modified_at: '2026-06-25T10:00:00Z' })
    ]
    expect(ids(makeSorter([{ property_id: '_modified_at', direction: 'ascending' }], schema)!(rows))).toEqual([
      'r2',
      'r1',
      'r3'
    ])
  })
})

describe('makeSorter — multi-key + null cases', () => {
  it('applies criteria in array order (primary, then secondary tiebreak)', () => {
    const rows = [
      makeRow('r1', { title: 'b', props: { prop_sel: 'a' } }),
      makeRow('r2', { title: 'a', props: { prop_sel: 'a' } }),
      makeRow('r3', { title: 'z', props: { prop_sel: 'b' } })
    ]
    const sorter = makeSorter(
      [
        { property_id: 'prop_sel', direction: 'ascending' },
        { property_id: '_title', direction: 'ascending' }
      ],
      schema
    )!
    expect(ids(sorter(rows))).toEqual(['r2', 'r1', 'r3'])
  })

  it('holds input order among full ties (stable)', () => {
    const rows = [
      makeRow('r1', { props: { prop_sel: 'a' } }),
      makeRow('r2', { props: { prop_sel: 'a' } }),
      makeRow('r3', { props: { prop_sel: 'a' } })
    ]
    expect(ids(makeSorter([{ property_id: 'prop_sel', direction: 'descending' }], schema)!(rows))).toEqual([
      'r1',
      'r2',
      'r3'
    ])
  })

  it('skips unsortable criteria but keeps usable ones', () => {
    const rows = [makeRow('r1', { props: { prop_num: 5 } }), makeRow('r2', { props: { prop_num: 2 } })]
    const sorter = makeSorter(
      [
        { property_id: 'prop_unknown', direction: 'ascending' },
        { property_id: 'prop_num', direction: 'ascending' }
      ],
      schema
    )
    expect(sorter).not.toBeNull()
    expect(ids(sorter!(rows))).toEqual(['r2', 'r1'])
  })

  it('returns null when there is no usable criterion', () => {
    expect(makeSorter(undefined, schema)).toBeNull()
    expect(makeSorter([], schema)).toBeNull()
    expect(makeSorter([{ property_id: 'prop_unknown', direction: 'ascending' }], schema)).toBeNull()
    expect(makeSorter([{ property_id: '_tier1', direction: 'ascending' }], schema)).toBeNull()
  })
})

describe('makeSorter — manual order tiebreaker (viewOrders, D-5/D-6)', () => {
  it('orders by the manual array when there is no sort (grouped-but-unsorted)', () => {
    const rows = [makeRow('a'), makeRow('b'), makeRow('c')]
    expect(ids(makeSorter(undefined, schema, ['c', 'a', 'b'])!(rows))).toEqual(['c', 'a', 'b'])
  })

  it('appends rows absent from the manual order, in input order, after the placed ones', () => {
    const rows = [makeRow('a'), makeRow('b'), makeRow('c'), makeRow('d')]
    expect(ids(makeSorter(undefined, schema, ['c', 'a'])!(rows))).toEqual(['c', 'a', 'b', 'd'])
  })

  it('breaks ties only AFTER the sort key — within an equal-key run (D-6)', () => {
    const rows = [
      makeRow('r1', { props: { prop_sel: 'a' } }),
      makeRow('r2', { props: { prop_sel: 'b' } }),
      makeRow('r3', { props: { prop_sel: 'a' } })
    ]
    const sorter = makeSorter([{ property_id: 'prop_sel', direction: 'ascending' }], schema, ['r3', 'r1'])!
    expect(ids(sorter(rows))).toEqual(['r3', 'r1', 'r2'])
  })

  it('cannot reorder across the sort key even if the manual order says so', () => {
    const rows = [makeRow('r1', { props: { prop_sel: 'a' } }), makeRow('r2', { props: { prop_sel: 'b' } })]
    const sorter = makeSorter([{ property_id: 'prop_sel', direction: 'ascending' }], schema, ['r2', 'r1'])!
    expect(ids(sorter(rows))).toEqual(['r1', 'r2'])
  })

  it('returns null when there is neither a sort nor a manual order', () => {
    expect(makeSorter(undefined, schema, [])).toBeNull()
    expect(makeSorter(undefined, schema, undefined)).toBeNull()
  })
})

describe('custom option order', () => {
  it('a criterion order ranks rows by the sequence, unknowns last, direction moot', () => {
    const rows = [
      makeRow('r1', { props: { prop_sel: 'a' } }),
      makeRow('r2', { props: { prop_sel: 'b' } }),
      makeRow('r3', { props: { prop_sel: 'zz' } }),
      makeRow('r4', { props: { prop_sel: 'c' } })
    ]
    const sorter = makeSorter([{ property_id: 'prop_sel', direction: 'descending', order: ['c', 'a', 'b'] }], schema)!
    expect(ids(sorter(rows))).toEqual(['r4', 'r1', 'r2', 'r3'])
  })
})

describe('resolvedSortCount', () => {
  it('counts only criteria buildCriterion resolves — dead and tier criteria cost nothing', () => {
    expect(resolvedSortCount(undefined, schema)).toBe(0)
    expect(resolvedSortCount([{ property_id: 'prop_gone', direction: 'ascending' }], schema)).toBe(0)
    expect(resolvedSortCount([{ property_id: '_tier1', direction: 'ascending' }], schema)).toBe(0)
    expect(
      resolvedSortCount(
        [
          { property_id: 'prop_sel', direction: 'ascending' },
          { property_id: 'prop_gone', direction: 'descending' }
        ],
        schema
      )
    ).toBe(1)
    expect(
      resolvedSortCount(
        [
          { property_id: '_title', direction: 'ascending' },
          { property_id: '_modified_at', direction: 'descending' }
        ],
        schema
      )
    ).toBe(2)
  })
})
