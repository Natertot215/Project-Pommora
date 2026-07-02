import { describe, expect, it } from 'vitest'
import { parseStyleAction, styleMenuItems, type StyleMenuContext } from './columnMenu'

const items = (type: StyleMenuContext['type'], current: StyleMenuContext['current'] = {}) =>
  styleMenuItems({ type, current })

describe('styleMenuItems', () => {
  it('status offers the three looks, current checked', () => {
    const rows = items('status', { look: 'capsule' })
    expect(rows.map((r) => [r.label, r.value])).toEqual([
      ['Pill', 'pill'],
      ['Capsule', 'capsule'],
      ['Checkbox', 'checkbox']
    ])
    expect(rows.find((r) => r.value === 'capsule')?.checked).toBe(true)
    expect(rows.every((r) => r.key === 'look')).toBe(true)
  })

  it('checkbox offers Checkbox/Switch; url Title/Full Link; file Filename/Full Path', () => {
    expect(items('checkbox', { look: 'checkbox' }).map((r) => r.label)).toEqual(['Checkbox', 'Switch'])
    expect(items('url', { look: 'full' }).map((r) => r.label)).toEqual(['Title', 'Full Link'])
    expect(items('file', { look: 'filename' }).map((r) => r.label)).toEqual(['Filename', 'Full Path'])
  })

  it('number offers the four formats keyed to number_format', () => {
    const rows = items('number', { number_format: 'percent' })
    expect(rows.map((r) => r.label)).toEqual(['Integer', 'Decimal', 'Percent', 'Currency'])
    expect(rows.find((r) => r.checked)?.value).toBe('percent')
    expect(rows.every((r) => r.key === 'number_format')).toBe(true)
  })

  it('datetime lists format-type names — dates, then times behind a separator', () => {
    const rows = items('datetime', { date_format: 'full', time_format: 'none' })
    expect(rows.map((r) => r.label)).toEqual([
      'Short Date',
      'Full Date',
      'DD/MM/YYYY',
      'MM/DD/YYYY',
      'None',
      '12 Hour',
      '24 Hour'
    ])
    expect(rows.find((r) => r.label === 'None')?.separatorBefore).toBe(true)
    expect(rows.filter((r) => r.checked).map((r) => r.label)).toEqual(['Full Date', 'None'])
  })

  it('last_edited_time shares the datetime menu', () => {
    expect(items('last_edited_time', {}).map((r) => r.label)).toContain('Short Date')
  })

  it('select/multi/context get no Style items', () => {
    expect(items('select')).toEqual([])
    expect(items('multi_select')).toEqual([])
    expect(items('context')).toEqual([])
  })
})

describe('parseStyleAction', () => {
  it('round-trips a style action string', () => {
    expect(parseStyleAction('style:look:capsule')).toEqual({ key: 'look', value: 'capsule' })
    expect(parseStyleAction('style:date_format:monthDayYear')).toEqual({ key: 'date_format', value: 'monthDayYear' })
  })

  it('rejects non-style or malformed actions', () => {
    expect(parseStyleAction('align:left')).toBeNull()
    expect(parseStyleAction('style:bogus_key:x')).toBeNull()
  })
})
