import { describe, it, expect } from 'vitest'
import type { ViewRow } from '@shared/types'
import type { FilterGroup } from '@shared/views'
import type { PropertyDefinition } from '@shared/properties'
import { applyFilter, FILTER_OPS } from './filter'

const schema: PropertyDefinition[] = [
  { id: 'prop_sel', name: 'Sel', type: 'select', select_options: [{ value: 'a', label: 'A' }, { value: 'b', label: 'B' }] },
  { id: 'prop_num', name: 'Num', type: 'number' },
  { id: 'prop_when', name: 'When', type: 'date' },
  { id: 'prop_done', name: 'Done', type: 'checkbox' },
  { id: 'prop_tags', name: 'Tags', type: 'multi_select' },
  { id: 'prop_rel', name: 'Rel', type: 'relation', relation_target: { kind: 'context_tier', tier: 1 } }
]

function row(
  id: string,
  opts: { props?: Record<string, unknown>; tier1?: string[]; modified_at?: string; created_at?: string } = {}
): ViewRow {
  return {
    id,
    title: id,
    path: `${id}.md`,
    frontmatter: {
      id,
      ...(opts.tier1 ? { tier1: opts.tier1 } : {}),
      ...(opts.modified_at ? { modified_at: opts.modified_at } : {}),
      ...(opts.created_at ? { created_at: opts.created_at } : {}),
      properties: opts.props ?? {}
    }
  }
}

const ids = (rows: ViewRow[], filter: FilterGroup | undefined): string[] =>
  applyFilter(rows, filter, schema).map((r) => r.id)

describe('applyFilter — match mode + recursion', () => {
  const rows = [
    row('r1', { props: { prop_sel: 'a', prop_num: 5 } }),
    row('r2', { props: { prop_sel: 'b', prop_num: 5 } }),
    row('r3', { props: { prop_sel: 'a', prop_num: 1 } })
  ]

  it('match all = AND', () => {
    expect(
      ids(rows, {
        match: 'all',
        rules: [
          { property_id: 'prop_sel', op: 'is', value: 'a' },
          { property_id: 'prop_num', op: 'greater_than', value: '3' }
        ]
      })
    ).toEqual(['r1'])
  })

  it('match any = OR', () => {
    expect(
      ids(rows, {
        match: 'any',
        rules: [
          { property_id: 'prop_sel', op: 'is', value: 'a' },
          { property_id: 'prop_num', op: 'greater_than', value: '3' }
        ]
      })
    ).toEqual(['r1', 'r2', 'r3'])
  })

  it('evaluates a nested (A AND B) OR C group', () => {
    expect(
      ids(rows, {
        match: 'any',
        rules: [
          {
            match: 'all',
            rules: [
              { property_id: 'prop_sel', op: 'is', value: 'a' },
              { property_id: 'prop_num', op: 'greater_than', value: '3' }
            ]
          },
          { property_id: 'prop_num', op: 'less_than', value: '2' }
        ]
      })
    ).toEqual(['r1', 'r3'])
  })

  it('empty rules pass everything (identity)', () => {
    expect(ids(rows, { match: 'all', rules: [] })).toEqual(['r1', 'r2', 'r3'])
  })

  it('undefined filter passes everything', () => {
    expect(ids(rows, undefined)).toEqual(['r1', 'r2', 'r3'])
  })
})

describe('applyFilter — per-type matrix', () => {
  it('number: comparison ops filter present values; an absent value is a no-op pass (Swift parity)', () => {
    const rows = [row('a', { props: { prop_num: 5 } }), row('b', { props: { prop_num: 1 } }), row('c', { props: {} })]
    // c (absent) passes every comparison op — a filter never excludes on an op it can't apply;
    // is_empty is how absence is actually filtered.
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_num', op: 'greater_than', value: '3' }] })).toEqual(['a', 'c'])
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_num', op: 'less_than', value: '3' }] })).toEqual(['b', 'c'])
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_num', op: 'is', value: '5' }] })).toEqual(['a', 'c'])
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_num', op: 'is_empty' }] })).toEqual(['c'])
  })

  it('date: comparison ops filter present values; an absent value is a no-op pass (Swift parity)', () => {
    const rows = [row('a', { props: { prop_when: '2026-06-20' } }), row('b', { props: { prop_when: '2026-06-10' } }), row('c', { props: {} })]
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_when', op: 'on_or_after', value: '2026-06-15' }] })).toEqual(['a', 'c'])
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_when', op: 'on_or_before', value: '2026-06-15' }] })).toEqual(['b', 'c'])
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_when', op: 'is_empty' }] })).toEqual(['c'])
  })

  it('select (text): is / contains / does_not_contain', () => {
    const rows = [row('a', { props: { prop_sel: 'alpha' } }), row('b', { props: { prop_sel: 'beta' } })]
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_sel', op: 'is', value: 'alpha' }] })).toEqual(['a'])
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_sel', op: 'contains', value: 'Lph' }] })).toEqual(['a'])
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_sel', op: 'does_not_contain', value: 'lph' }] })).toEqual(['b'])
  })

  it('multi_select: membership via contains / is_empty', () => {
    const rows = [row('a', { props: { prop_tags: ['x', 'y'] } }), row('b', { props: { prop_tags: ['z'] } }), row('c', { props: {} })]
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_tags', op: 'contains', value: 'x' }] })).toEqual(['a'])
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_tags', op: 'is_empty' }] })).toEqual(['c'])
  })

  it('checkbox supports is / is_empty; is_not_empty is a no-op pass (Swift parity)', () => {
    const rows = [row('t', { props: { prop_done: true } }), row('f', { props: { prop_done: false } }), row('n', { props: {} })]
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_done', op: 'is', value: 'true' }] })).toEqual(['t'])
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_done', op: 'is_empty' }] })).toEqual(['n'])
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_done', op: 'is_not_empty' }] })).toEqual(['t', 'f', 'n'])
  })

  it('tier filters by membership; user relation is/contains are no-op passes', () => {
    const rA = row('rA', { tier1: ['area1'] })
    const rB = row('rB', { tier1: ['area2'] })
    const rRel = row('rRel', { props: { prop_rel: [{ $rel: 'x' }] } })
    expect(ids([rA, rB], { match: 'all', rules: [{ property_id: '_tier1', op: 'contains', value: 'area1' }] })).toEqual(['rA'])
    expect(ids([rA, rRel], { match: 'all', rules: [{ property_id: 'prop_rel', op: 'is', value: 'x' }] })).toEqual(['rA', 'rRel'])
    expect(ids([rA, rRel], { match: 'all', rules: [{ property_id: 'prop_rel', op: 'is_not_empty' }] })).toEqual(['rRel'])
  })

  it('_modified_at filters as a date, falling back to created_at', () => {
    const rMod = row('rMod', { modified_at: '2026-06-20T10:00:00Z' })
    const rCreated = row('rCreated', { created_at: '2026-06-25T10:00:00Z' })
    expect(
      ids([rMod, rCreated], { match: 'all', rules: [{ property_id: '_modified_at', op: 'on_or_after', value: '2026-06-22' }] })
    ).toEqual(['rCreated'])
  })
})

describe('applyFilter — no-op passes', () => {
  const rows = [row('a', { props: { prop_sel: 'a' } })]

  it('an unknown operator passes', () => {
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_sel', op: 'totally_made_up', value: 'a' }] })).toEqual(['a'])
  })

  it('a rule for a property absent from the schema passes', () => {
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_ghost', op: 'is', value: 'a' }] })).toEqual(['a'])
  })

  it('a _title rule passes (not in the filter matrix, Swift parity)', () => {
    expect(ids(rows, { match: 'all', rules: [{ property_id: '_title', op: 'contains', value: 'zzz' }] })).toEqual(['a'])
  })

  it('exposes snake_case op raw strings', () => {
    expect(FILTER_OPS.onOrAfter).toBe('on_or_after')
    expect(FILTER_OPS.doesNotContain).toBe('does_not_contain')
    expect(FILTER_OPS.isNotEmpty).toBe('is_not_empty')
  })
})
