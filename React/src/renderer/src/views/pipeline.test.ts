import { describe, it, expect } from 'vitest'
import type { ViewRow, ViewSpec } from '@shared/types'
import { resolveView } from './pipeline'

const row = (
  title: string,
  extra: Partial<ViewRow> = {}
): ViewRow => ({
  id: title.toLowerCase().replace(/\s+/g, '-'),
  title,
  path: `Vault/${title}.md`,
  ...extra
})

const rows: ViewRow[] = [
  row('Banana', { frontmatter: { status: 'done', priority: 2 } }),
  row('apple', { frontmatter: { status: 'todo', priority: 10 } }),
  row('Cherry', { frontmatter: { status: 'done' } }), // no priority
  row('damson', { frontmatter: { status: 'todo', priority: 1 } })
]

describe('resolveView — defaults', () => {
  it('no spec ⇒ one implicit __all__ group, original order, no mutation', () => {
    const input = rows.slice()
    const out = resolveView(input)
    expect(out).toHaveLength(1)
    expect(out[0].key).toBe('__all__')
    expect(out[0].label).toBe('All')
    expect(out[0].rows.map((r) => r.title)).toEqual(['Banana', 'apple', 'Cherry', 'damson'])
    // input array + identity preserved (pure)
    expect(input.map((r) => r.title)).toEqual(['Banana', 'apple', 'Cherry', 'damson'])
  })
})

describe('resolveView — sort', () => {
  it('sorts by intrinsic title, case-insensitive, ascending', () => {
    const out = resolveView(rows, { sort: { field: 'title', direction: 'asc' } })
    expect(out[0].rows.map((r) => r.title)).toEqual(['apple', 'Banana', 'Cherry', 'damson'])
  })

  it('sorts descending', () => {
    const out = resolveView(rows, { sort: { field: 'title', direction: 'desc' } })
    expect(out[0].rows.map((r) => r.title)).toEqual(['damson', 'Cherry', 'Banana', 'apple'])
  })

  it('sorts a frontmatter field numerically (numeric collation)', () => {
    const out = resolveView(rows, { sort: { field: 'priority', direction: 'asc' } })
    // priorities: 1, 2, 10, (empty) — empties last regardless of direction
    expect(out[0].rows.map((r) => r.title)).toEqual(['damson', 'Banana', 'apple', 'Cherry'])
  })

  it('keeps empty values last even when descending', () => {
    const out = resolveView(rows, { sort: { field: 'priority', direction: 'desc' } })
    expect(out[0].rows.map((r) => r.title)).toEqual(['apple', 'Banana', 'damson', 'Cherry'])
  })

  it('is stable for equal keys (preserves input order)', () => {
    const out = resolveView(rows, { sort: { field: 'status', direction: 'asc' } })
    // 'done' rows: Banana, Cherry (input order) ; 'todo' rows: apple, damson
    expect(out[0].rows.map((r) => r.title)).toEqual(['Banana', 'Cherry', 'apple', 'damson'])
  })
})

describe('resolveView — group', () => {
  it('groups by a frontmatter field, preserving first-seen group order', () => {
    const out = resolveView(rows, { groupBy: 'status' })
    expect(out.map((g) => g.key)).toEqual(['done', 'todo'])
    expect(out.map((g) => g.label)).toEqual(['done', 'todo'])
    expect(out[0].rows.map((r) => r.title)).toEqual(['Banana', 'Cherry'])
    expect(out[1].rows.map((r) => r.title)).toEqual(['apple', 'damson'])
  })

  it('buckets absent values into the Empty group', () => {
    const out = resolveView(rows, { groupBy: 'priority' })
    const empty = out.find((g) => g.key === '')
    expect(empty?.label).toBe('Empty')
    expect(empty?.rows.map((r) => r.title)).toEqual(['Cherry'])
  })

  it('sorts within each group', () => {
    const out = resolveView(rows, { groupBy: 'status', sort: { field: 'title', direction: 'asc' } })
    expect(out[0].rows.map((r) => r.title)).toEqual(['Banana', 'Cherry'])
    expect(out[1].rows.map((r) => r.title)).toEqual(['apple', 'damson'])
  })
})

describe('resolveView — filter', () => {
  it('filters with equals (case-insensitive)', () => {
    const out = resolveView(rows, { filters: [{ field: 'status', operator: 'equals', value: 'DONE' }] })
    expect(out[0].rows.map((r) => r.title)).toEqual(['Banana', 'Cherry'])
  })

  it('filters with contains on title', () => {
    const out = resolveView(rows, { filters: [{ field: 'title', operator: 'contains', value: 'a' }] })
    expect(out[0].rows.map((r) => r.title)).toEqual(['Banana', 'apple', 'damson'])
  })

  it('filters with notEquals', () => {
    const out = resolveView(rows, { filters: [{ field: 'status', operator: 'notEquals', value: 'done' }] })
    expect(out[0].rows.map((r) => r.title)).toEqual(['apple', 'damson'])
  })

  it('isEmpty / isNotEmpty key off the resolved cell text', () => {
    const empty = resolveView(rows, { filters: [{ field: 'priority', operator: 'isEmpty' }] })
    expect(empty[0].rows.map((r) => r.title)).toEqual(['Cherry'])
    const notEmpty = resolveView(rows, { filters: [{ field: 'priority', operator: 'isNotEmpty' }] })
    expect(notEmpty[0].rows.map((r) => r.title)).toEqual(['Banana', 'apple', 'damson'])
  })

  it('ANDs multiple rules', () => {
    const out = resolveView(rows, {
      filters: [
        { field: 'status', operator: 'equals', value: 'todo' },
        { field: 'title', operator: 'contains', value: 'a' }
      ]
    })
    expect(out[0].rows.map((r) => r.title)).toEqual(['apple', 'damson'])
  })

  it('handles array frontmatter via joined text (contains a member)', () => {
    const tagged: ViewRow[] = [
      row('X', { frontmatter: { tags: ['red', 'blue'] } }),
      row('Y', { frontmatter: { tags: ['green'] } })
    ]
    const out = resolveView(tagged, { filters: [{ field: 'tags', operator: 'contains', value: 'blue' }] })
    expect(out[0].rows.map((r) => r.title)).toEqual(['X'])
  })
})

describe('resolveView — combined filter → group → sort', () => {
  it('applies all three in order', () => {
    const spec: ViewSpec = {
      filters: [{ field: 'priority', operator: 'isNotEmpty' }],
      groupBy: 'status',
      sort: { field: 'title', direction: 'desc' }
    }
    const out = resolveView(rows, spec)
    // Cherry filtered out (no priority). done -> Banana ; todo -> apple, damson
    expect(out.map((g) => g.key)).toEqual(['done', 'todo'])
    expect(out[0].rows.map((r) => r.title)).toEqual(['Banana'])
    expect(out[1].rows.map((r) => r.title)).toEqual(['damson', 'apple'])
  })
})
