import { describe, expect, it } from 'vitest'
import type { IconName } from '@renderer/design-system/symbols'
import type { ViewType } from '@shared/views'
import { iconForTypeSwitch } from './viewIcon'

const GLYPH: Record<ViewType, IconName> = {
  table: 'table',
  cards: 'cards-grid',
  list: 'list-rounded',
  gallery: 'layout-dashboard',
  calendar: 'calendar-days',
  timeline: 'chart-gantt',
}

describe('iconForTypeSwitch', () => {
  it('re-icons a view that still wears the old default (table → cards)', () => {
    expect(iconForTypeSwitch('table', 'table', 'cards', GLYPH)).toBe('cards-grid')
    expect(iconForTypeSwitch('cards-grid', 'cards', 'table', GLYPH)).toBe('table')
  })

  it('treats the legacy tablecells glyph and an absent icon as the default', () => {
    expect(iconForTypeSwitch('tablecells', 'table', 'cards', GLYPH)).toBe('cards-grid')
    expect(iconForTypeSwitch(undefined, 'table', 'cards', GLYPH)).toBe('cards-grid')
  })

  it('keeps a custom icon (returns undefined)', () => {
    expect(iconForTypeSwitch('star', 'table', 'cards', GLYPH)).toBeUndefined()
  })
})
