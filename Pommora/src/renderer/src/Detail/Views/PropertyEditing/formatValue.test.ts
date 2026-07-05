import { describe, expect, it } from 'vitest'
import { fileLabel, formatDate, formatNumber } from './formatValue'

describe('formatDate', () => {
  it('renders the four Swift date formats', () => {
    expect(formatDate('2026-03-01', 'short', 'none')).toBe('March 1st')
    expect(formatDate('2026-03-01', 'full', 'none')).toBe('Sunday, March 1st 2026')
    expect(formatDate('2026-03-01', 'dayMonthYear', 'none')).toBe('01/03/2026')
    expect(formatDate('2026-03-01', 'monthDayYear', 'none')).toBe('03/01/2026')
  })

  it.each([
    [1, '1st'],
    [2, '2nd'],
    [3, '3rd'],
    [4, '4th'],
    [11, '11th'],
    [12, '12th'],
    [13, '13th'],
    [21, '21st'],
    [22, '22nd'],
    [23, '23rd'],
    [31, '31st']
  ])('ordinal day %i renders %s', (day, expected) => {
    expect(formatDate(`2026-03-${String(day).padStart(2, '0')}`, 'short', 'none')).toBe(`March ${expected}`)
  })

  it('appends the time per the time format when the value carries one', () => {
    expect(formatDate('2026-03-01T15:45:00', 'short', 'twelveHour')).toBe('March 1st 3:45 PM')
    expect(formatDate('2026-03-01T15:45:00', 'short', 'twentyFourHour')).toBe('March 1st 15:45')
    expect(formatDate('2026-03-01T15:45:00', 'short', 'none')).toBe('March 1st')
  })

  it('never invents a time for a date-only value', () => {
    expect(formatDate('2026-03-01', 'short', 'twelveHour')).toBe('March 1st')
  })

  it('falls back to the raw string for an unparseable value', () => {
    expect(formatDate('not-a-date', 'short', 'none')).toBe('not-a-date')
  })
})

describe('formatNumber', () => {
  it('renders each Swift number format', () => {
    expect(formatNumber(1234.5, 'integer')).toBe('1,235')
    expect(formatNumber(1234.5, 'decimal')).toBe('1,234.5')
    expect(formatNumber(0.42, 'percent')).toBe('42%')
    expect(formatNumber(1234.5, 'currency')).toBe('$1,234.50')
  })

  it('integers keep no fraction; decimals keep locale grouping', () => {
    expect(formatNumber(7, 'integer')).toBe('7')
    expect(formatNumber(1000000, 'decimal')).toBe('1,000,000')
  })
})

describe('fileLabel', () => {
  it('the filename look strips the directory; the path look keeps it', () => {
    expect(fileLabel({ path: 'Assets/Photos/trip.png' }, 'filename')).toBe('trip.png')
    expect(fileLabel({ path: 'Assets/Photos/trip.png' }, 'path')).toBe('Assets/Photos/trip.png')
    expect(fileLabel({ path: 'root.pdf' }, 'filename')).toBe('root.pdf')
  })
})
