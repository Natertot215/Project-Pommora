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
    expect(resolveFieldValue(row, '_title')).toEqual({ kind: 'select', value: 'My Page' })
    expect(resolveFieldValue(row, '_modified_at')).toEqual({
      kind: 'datetime',
      value: '2026-06-20T10:00:00Z'
    })
    expect(resolveFieldValue(row, '_tier1')).toEqual({ kind: 'relation', value: ['01AREA'] })
    expect(resolveFieldValue(row, '_tier2')).toEqual({ kind: 'relation', value: [] })
  })

  it('routes user properties through the on-disk codec, trusting its kind', () => {
    expect(resolveFieldValue(row, 'prop_status')).toEqual({ kind: 'status', value: 'in_progress' })
    expect(resolveFieldValue(row, 'prop_sel')).toEqual({ kind: 'select', value: 'opt_a' })
    expect(resolveFieldValue(row, 'prop_when')).toEqual({
      kind: 'datetime',
      value: '2026-06-15T09:00:00Z'
    })
    expect(resolveFieldValue(row, 'prop_num')).toEqual({ kind: 'number', value: 42 })
  })

  it('returns null for an absent property and for the unbranched _status', () => {
    expect(resolveFieldValue(row, 'prop_absent')).toEqual({ kind: 'null' })
    expect(resolveFieldValue(row, '_status')).toEqual({ kind: 'null' })
  })

  it('degrades a malformed value to null rather than throwing (never poison a view)', () => {
    expect(resolveFieldValue(row, 'prop_bad')).toEqual({ kind: 'null' })
  })

  it('returns null for _modified_at when frontmatter has no timestamp', () => {
    const bare: ViewRow = { id: 'x', title: 'X', path: 'x.md', frontmatter: { id: 'x' } }
    expect(resolveFieldValue(bare, '_modified_at')).toEqual({ kind: 'null' })
  })
})
