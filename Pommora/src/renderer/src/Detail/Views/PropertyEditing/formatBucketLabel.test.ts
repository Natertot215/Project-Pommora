import { describe, expect, it } from 'vitest'
import { formatBucketLabel } from './formatValue'

describe('formatBucketLabel', () => {
  it('worded formats: month bucket reads written', () => {
    expect(formatBucketLabel('2026-07', 'month', 'full', 'dash')).toBe('July 2026')
    expect(formatBucketLabel('2026-07', 'month', 'short', 'slash')).toBe('July 2026')
  })

  it('numeric formats: month bucket uses the separator', () => {
    expect(formatBucketLabel('2026-07', 'month', 'monthDayYear', 'dash')).toBe('07-2026')
    expect(formatBucketLabel('2026-07', 'month', 'monthDayYear', 'slash')).toBe('07/2026')
    expect(formatBucketLabel('2026-07', 'month', 'dayMonthYear', 'dash')).toBe('07-2026')
  })

  it('day buckets ride formatDate; dash swaps numeric separators', () => {
    expect(formatBucketLabel('2026-07-09', 'day', 'monthDayYear', 'dash')).toBe('07-09-2026')
    expect(formatBucketLabel('2026-07-09', 'day', 'monthDayYear', 'slash')).toBe('07/09/2026')
    expect(formatBucketLabel('2026-07-09', 'day', 'full', 'dash')).toBe('July 9th, 2026')
  })

  it('year + week buckets', () => {
    expect(formatBucketLabel('2026', 'year', 'full', 'dash')).toBe('2026')
    expect(formatBucketLabel('2026-W28', 'week', 'full', 'dash')).toBe('Week 28, 2026')
    expect(formatBucketLabel('2026-W28', 'week', 'monthDayYear', 'dash')).toBe('W28-2026')
    expect(formatBucketLabel('2026-W28', 'week', 'monthDayYear', 'slash')).toBe('W28/2026')
  })

  it('unparseable keys fall back raw', () => {
    expect(formatBucketLabel('junk', 'month', 'full', 'dash')).toBe('junk')
    expect(formatBucketLabel('junk', 'week', 'monthDayYear', 'slash')).toBe('junk')
  })
})
