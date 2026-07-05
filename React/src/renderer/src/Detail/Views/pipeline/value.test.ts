import { describe, it, expect } from 'vitest'
import type { ViewRow } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { declaredType, resolveFieldValue } from './value'

const schema: PropertyDefinition[] = [
  { id: 'prop_status', name: 'Status', type: 'status' },
  { id: 'prop_sel', name: 'Sel', type: 'select' },
  { id: 'prop_when', name: 'When', type: 'datetime' },
  { id: 'prop_num', name: 'Num', type: 'number' }
]

// Every assertion below resolves against `schema` (the declared-type coercion needs it) — one bound
// helper keeps them terse. The coercion's own cases pass a purpose-built schema to resolveFieldValue.
const rfv = (r: ViewRow, p: string) => resolveFieldValue(r, p, schema)

const row: ViewRow = {
  id: '01ROW',
  title: 'My Page',
  path: 'Col/my-page.md',
  frontmatter: {
    id: '01ROW',
    modified_at: '2026-06-20T10:00:00Z',
    tier1: ['01AREA'],
    properties: {
      prop_status: { $status: 'in_progress' },
      prop_sel: 'opt_a',
      prop_when: '2026-06-15T09:00:00Z',
      prop_num: 42,
      prop_bad: [1, 'mixed']
    }
  }
}

describe('declaredType', () => {
  it('maps reserved columns to the type/sentinel sort+group+filter switch on', () => {
    expect(declaredType('_title', schema)).toBe('title')
    expect(declaredType('_modified_at', schema)).toBe('last_edited_time')
    expect(declaredType('_tier1', schema)).toBe('tier')
    expect(declaredType('_tier3', schema)).toBe('tier')
  })

  it('reads user property types from the schema (snake_case PropertyType)', () => {
    expect(declaredType('prop_status', schema)).toBe('status')
    expect(declaredType('prop_sel', schema)).toBe('select')
    expect(declaredType('prop_num', schema)).toBe('number')
    expect(declaredType('prop_when', schema)).toBe('datetime')
  })

  it('gives _status no special branch, and unknown ids resolve undefined', () => {
    expect(declaredType('_status', schema)).toBeUndefined()
    expect(declaredType('prop_absent', schema)).toBeUndefined()
  })
})

describe('resolveFieldValue', () => {
  it('reads reserved columns from intrinsic/frontmatter fields', () => {
    expect(rfv(row, '_title')).toEqual({ kind: 'select', value: 'My Page' })
    expect(rfv(row, '_modified_at')).toEqual({
      kind: 'datetime',
      value: '2026-06-20T10:00:00Z'
    })
    expect(rfv(row, '_tier1')).toEqual({ kind: 'context', value: ['01AREA'] })
    expect(rfv(row, '_tier2')).toEqual({ kind: 'context', value: [] })
  })

  it('routes user properties through the on-disk codec, trusting its kind', () => {
    expect(rfv(row, 'prop_status')).toEqual({ kind: 'status', value: 'in_progress' })
    expect(rfv(row, 'prop_sel')).toEqual({ kind: 'select', value: 'opt_a' })
    expect(rfv(row, 'prop_when')).toEqual({
      kind: 'datetime',
      value: '2026-06-15T09:00:00Z'
    })
    expect(rfv(row, 'prop_num')).toEqual({ kind: 'number', value: 42 })
  })

  it('returns null for an absent property and for the unbranched _status', () => {
    expect(rfv(row, 'prop_absent')).toEqual({ kind: 'null' })
    expect(rfv(row, '_status')).toEqual({ kind: 'null' })
  })

  it('degrades a malformed value to null rather than throwing (never poison a view)', () => {
    expect(rfv(row, 'prop_bad')).toEqual({ kind: 'null' })
  })

  it('returns null for _modified_at when frontmatter has no timestamp', () => {
    const bare: ViewRow = { id: 'x', title: 'X', path: 'x.md', frontmatter: { id: 'x' } }
    expect(rfv(bare, '_modified_at')).toEqual({ kind: 'null' })
  })
})

describe('resolveFieldValue memoization', () => {
  it('returns the SAME resolved object for repeat calls on one frontmatter (parse-once)', () => {
    const row: ViewRow = {
      id: 'p1',
      title: 'One',
      path: 'C/One.md',
      frontmatter: { id: 'p1', properties: { prop_s: { $status: 'open' } }, tier1: ['a'] }
    }
    // Identity-stability holds for NON-coerced kinds (the cached parse is returned as-is, tested here).
    // A coerced plain-string kind (url/select/datetime re-tagged to the column) returns a FRESH object
    // each call — the expensive parse stays cached, only the O(1) re-tag is per-call. No consumer keys
    // identity on the resolved value (Cell resolves fresh; rowById keys on row.id), so this is contractual.
    expect(rfv(row, 'prop_s')).toBe(rfv(row, 'prop_s'))
    expect(rfv(row, '_tier1')).toBe(rfv(row, '_tier1'))
  })

  it('a fresh frontmatter identity re-resolves (the optimistic-patch / reload contract)', () => {
    const fm1 = { id: 'p1', properties: { prop_s: { $status: 'open' } } }
    const fm2 = { id: 'p1', properties: { prop_s: { $status: 'done' } } }
    const rowAt = (frontmatter: ViewRow['frontmatter']): ViewRow => ({ id: 'p1', title: 'One', path: 'C/One.md', frontmatter })
    const before = rfv(rowAt(fm1), 'prop_s')
    const after = rfv(rowAt(fm2), 'prop_s')
    expect(before).toMatchObject({ kind: 'status', value: 'open' })
    expect(after).toMatchObject({ kind: 'status', value: 'done' })
  })

  it('_title never caches — a rename with an unchanged frontmatter object shows the new title', () => {
    const fm = { id: 'p1' }
    const a = rfv({ id: 'p1', title: 'Old', path: 'C/Old.md', frontmatter: fm }, '_title')
    const b = rfv({ id: 'p1', title: 'New', path: 'C/New.md', frontmatter: fm }, '_title')
    expect(a).toEqual({ kind: 'select', value: 'Old' })
    expect(b).toEqual({ kind: 'select', value: 'New' })
  })
})

describe('resolveFieldValue — declared-type coercion (the plain-string kinds follow the column)', () => {
  const typedSchema: PropertyDefinition[] = [
    { id: 'prop_link', name: 'Link', type: 'url' },
    { id: 'prop_tag', name: 'Tag', type: 'select' }
  ]
  const rowOf = (properties: Record<string, unknown>): ViewRow => ({
    id: 'r',
    title: 'R',
    path: 'C/r.md',
    frontmatter: { id: 'r', properties }
  })

  it('a url column reads an aliased [alias](url) value as url, not a select pill', () => {
    expect(resolveFieldValue(rowOf({ prop_link: '[Docs](https://example.com)' }), 'prop_link', typedSchema)).toEqual({
      kind: 'url',
      value: '[Docs](https://example.com)'
    })
  })

  it('a url column reads a bare URL as url (shape already agrees — no re-tag)', () => {
    expect(resolveFieldValue(rowOf({ prop_link: 'https://example.com' }), 'prop_link', typedSchema)).toEqual({
      kind: 'url',
      value: 'https://example.com'
    })
  })

  it('a select column keeps a link-shaped value as select (build-breaker #2 — never stolen to url)', () => {
    expect(resolveFieldValue(rowOf({ prop_tag: '[URGENT](tel:911)' }), 'prop_tag', typedSchema)).toEqual({
      kind: 'select',
      value: '[URGENT](tel:911)'
    })
  })

  it('a plain select option is untouched', () => {
    expect(resolveFieldValue(rowOf({ prop_tag: 'opt_a' }), 'prop_tag', typedSchema)).toEqual({
      kind: 'select',
      value: 'opt_a'
    })
  })
})
