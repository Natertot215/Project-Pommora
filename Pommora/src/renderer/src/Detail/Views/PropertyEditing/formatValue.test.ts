import { describe, expect, it } from 'vitest'
import { condensedDate, fileLabel, formatDate, formatNumber, numberDivisor } from './formatValue'

describe('formatDate', () => {
  it('renders the four Swift date formats', () => {
    expect(formatDate('2026-03-01', 'short', 'none')).toBe('March 1st')
    expect(formatDate('2026-03-01', 'full', 'none')).toBe('March 1st, 2026')
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
    [31, '31st'],
  ])('ordinal day %i renders %s', (day, expected) => {
    expect(formatDate(`2026-03-${String(day).padStart(2, '0')}`, 'short', 'none')).toBe(
      `March ${expected}`,
    )
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

describe('formatDate weekday + reshaped full', () => {
  const iso = '2026-07-06' // a Monday
  it('full is weekday-free: Month Ordinal, Year', () => {
    expect(formatDate(iso, 'full', 'none')).toBe('July 6th, 2026')
  })
  it('short is Month Ordinal', () => {
    expect(formatDate(iso, 'short', 'none')).toBe('July 6th')
  })
  it('long weekday prepends on full', () => {
    expect(formatDate(iso, 'full', 'none', 'long')).toBe('Monday, July 6th, 2026')
  })
  it('short weekday prepends on short', () => {
    expect(formatDate(iso, 'short', 'none', 'short')).toBe('Mon, July 6th')
  })
  it('weekday is ignored on numeric formats', () => {
    expect(formatDate(iso, 'monthDayYear', 'none', 'long')).toBe('07/06/2026')
  })
  it('weekday none adds nothing', () => {
    expect(formatDate(iso, 'full', 'none', 'none')).toBe('July 6th, 2026')
  })
})

describe('formatDate relative', () => {
  const now = new Date('2026-07-06T12:00:00')
  const rel = (iso: string, time: 'none' | 'twelveHour' = 'none') =>
    formatDate(iso, 'relative', time, 'none', now)
  it('today / yesterday / tomorrow', () => {
    expect(rel('2026-07-06')).toBe('Today')
    expect(rel('2026-07-05')).toBe('Yesterday')
    expect(rel('2026-07-07')).toBe('Tomorrow')
  })
  it('within a week counts days both directions', () => {
    expect(rel('2026-07-03')).toBe('3 Days Ago')
    expect(rel('2026-07-09')).toBe('3 Days from now')
  })
  it('past a week rolls to weeks / months / years', () => {
    expect(rel('2026-06-20')).toBe('2 Weeks Ago')
    expect(rel('2026-04-06')).toBe('3 Months Ago')
    expect(rel('2024-07-06')).toBe('2 Years Ago')
  })
  it('time-shown appends the clock within a week, drops it past a week', () => {
    expect(rel('2026-07-06T15:30:00', 'twelveHour')).toBe('Today at 3:30 PM')
    expect(rel('2026-07-05T15:30:00', 'twelveHour')).toBe('Yesterday at 3:30 PM')
    expect(rel('2026-06-20T15:30:00', 'twelveHour')).toBe('2 Weeks Ago')
  })
  it('condensedDate treats relative as the worded short form (never shown relative in the picker)', () => {
    expect(condensedDate('2026-07-06', 'relative', true)).toBe('July 6th')
  })
})

describe('formatNumber', () => {
  it('groups by default and honours separators off', () => {
    expect(formatNumber(1234.5, { number_family: 'number', number_separators: true })).toBe(
      '1,234.5',
    )
    expect(formatNumber(1234.5, { number_family: 'number', number_separators: false })).toBe(
      '1234.5',
    )
  })
  it('hidden decimals show as an integer; a fixed count pads', () => {
    expect(formatNumber(3.14, { number_decimals: 'hidden' })).toBe('3')
    expect(formatNumber(3, { number_decimals: 2 })).toBe('3.00')
  })
  it('percent is literal + "%", never ×100', () => {
    expect(formatNumber(30, { number_family: 'percent' })).toBe('30%')
  })
  it('currency uses the chosen ISO code', () => {
    expect(
      formatNumber(1234, { number_family: 'currency', number_currency: 'GBP', number_decimals: 2 }),
    ).toBe('£1,234.00')
  })
  it('fraction renders "N out of Value"', () => {
    expect(
      formatNumber(3, { number_family: 'number', number_fraction: true, number_denominator: 10 }),
    ).toBe('3 out of 10')
  })
})

describe('numberDivisor', () => {
  it('is 100 for percent, the denominator for fraction, undefined otherwise', () => {
    expect(numberDivisor({ number_family: 'percent' })).toBe(100)
    expect(
      numberDivisor({ number_family: 'number', number_fraction: true, number_denominator: 10 }),
    ).toBe(10)
    expect(numberDivisor({ number_family: 'number', number_fraction: false })).toBeUndefined()
  })
  it('guards a zero / missing denominator', () => {
    expect(
      numberDivisor({ number_family: 'number', number_fraction: true, number_denominator: 0 }),
    ).toBeUndefined()
    expect(numberDivisor({ number_family: 'number', number_fraction: true })).toBeUndefined()
  })
})

describe('fileLabel', () => {
  it('the filename look strips the directory; the path look keeps it', () => {
    expect(fileLabel({ path: 'Assets/Photos/trip.png' }, 'filename')).toBe('trip.png')
    expect(fileLabel({ path: 'Assets/Photos/trip.png' }, 'path')).toBe('Assets/Photos/trip.png')
    expect(fileLabel({ path: 'root.pdf' }, 'filename')).toBe('root.pdf')
  })
})
