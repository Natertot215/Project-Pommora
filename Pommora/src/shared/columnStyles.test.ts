import { describe, expect, it } from 'vitest'
import { columnStyle, defaultStyleFor } from './columnStyles'

describe('defaultStyleFor', () => {
  it('gives each look-bearing type its default look', () => {
    expect(defaultStyleFor('status')).toEqual({ look: 'pill' })
    expect(defaultStyleFor('checkbox')).toEqual({ look: 'checkbox' })
    expect(defaultStyleFor('url')).toEqual({ look: 'full' })
    expect(defaultStyleFor('file')).toEqual({ look: 'filename' })
  })

  it('gives the date-shaped types the full-date, no-time format defaults', () => {
    expect(defaultStyleFor('datetime')).toEqual({ date_format: 'full', time_format: 'none' })
    expect(defaultStyleFor('last_edited_time')).toEqual({ date_format: 'full', time_format: 'none' })
  })

  it('numbers default to decimal', () => {
    expect(defaultStyleFor('number')).toEqual({ number_format: 'decimal' })
  })

  it('select/multi and unknown types are not style-addressable', () => {
    expect(defaultStyleFor('select')).toEqual({})
    expect(defaultStyleFor('multi_select')).toEqual({})
    expect(defaultStyleFor(undefined)).toEqual({})
  })
})

describe('columnStyle codec', () => {
  it('round-trips a full entry', () => {
    const entry = { look: 'capsule', date_format: 'short', time_format: 'twelveHour', number_format: 'percent' }
    expect(columnStyle.parse(entry)).toEqual(entry)
  })

  it('drops an unknown enum value instead of sinking the entry', () => {
    expect(columnStyle.parse({ look: 'zebra', number_format: 'integer' })).toEqual({ number_format: 'integer' })
  })

  it('lets unknown keys ride through', () => {
    expect(columnStyle.parse({ look: 'pill', swift_only: true })).toEqual({ look: 'pill', swift_only: true })
  })
})
