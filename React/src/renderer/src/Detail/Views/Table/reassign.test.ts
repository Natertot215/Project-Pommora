import { describe, it, expect } from 'vitest'
import { UNGROUPED } from '@shared/types'
import { groupKeyToValue, REASSIGNABLE_GROUP_TYPES } from './reassign'

describe('groupKeyToValue — destination group key → PropertyValue (D-4)', () => {
  it('status: the key is the status value', () => {
    expect(groupKeyToValue('done', 'status')).toEqual({ kind: 'status', value: 'done' })
  })

  it('select: the key is the select value', () => {
    expect(groupKeyToValue('red', 'select')).toEqual({ kind: 'select', value: 'red' })
  })

  it('checkbox: the true/false bucket maps to the boolean', () => {
    expect(groupKeyToValue('true', 'checkbox')).toEqual({ kind: 'checkbox', value: true })
    expect(groupKeyToValue('false', 'checkbox')).toEqual({ kind: 'checkbox', value: false })
  })

  it('the no-value band clears the property (null)', () => {
    expect(groupKeyToValue(UNGROUPED, 'status')).toBeNull()
    expect(groupKeyToValue(UNGROUPED, 'select')).toBeNull()
  })

  it('an un-reassignable type yields null (caller gates these out)', () => {
    expect(groupKeyToValue('2026-06', 'date')).toBeNull()
    expect(groupKeyToValue('x', undefined)).toBeNull()
  })

  it('REASSIGNABLE_GROUP_TYPES is exactly status/select/checkbox', () => {
    expect([...REASSIGNABLE_GROUP_TYPES].sort()).toEqual(['checkbox', 'select', 'status'])
  })
})
