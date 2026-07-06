import { describe, it, expect } from 'vitest'
import { coerceOpenIn, coerceViewButton, coerceViewStyle, pageCollectionSidecar, pageSetSidecar } from './schemas'

describe('open_in coercion', () => {
  it('coerces legacy window/compact to the new enum', () => {
    expect(coerceOpenIn('window')).toBe('full-page')
    expect(coerceOpenIn('compact')).toBe('page-preview')
  })
  it('passes new values through and drops junk / absent', () => {
    expect(coerceOpenIn('full-page')).toBe('full-page')
    expect(coerceOpenIn('page-preview')).toBe('page-preview')
    expect(coerceOpenIn('nonsense')).toBeUndefined()
    expect(coerceOpenIn(undefined)).toBeUndefined()
  })
})

describe('view_button / view_style coercion', () => {
  it('accepts valid values, drops junk', () => {
    expect(coerceViewButton('labeled')).toBe('labeled')
    expect(coerceViewButton('nope')).toBeUndefined()
    expect(coerceViewStyle('toolbar')).toBe('toolbar')
    expect(coerceViewStyle('nope')).toBeUndefined()
  })
})

describe('container sidecar round-trip', () => {
  it('collection keeps open_in (coerced) + view_button + view_style + foreign keys', () => {
    const c = pageCollectionSidecar.parse({ id: 'c1', open_in: 'window', view_button: 'labeled', view_style: 'toolbar', foreign: 'kept' })
    expect(c.open_in).toBe('full-page')
    expect(c.view_button).toBe('labeled')
    expect(c.view_style).toBe('toolbar')
    expect((c as Record<string, unknown>).foreign).toBe('kept')
  })
  it('set keeps view_button + view_style (no open_in field)', () => {
    const s = pageSetSidecar.parse({ id: 's1', parent_id: 'c1', view_button: 'icon', view_style: 'dropdown' })
    expect(s.view_button).toBe('icon')
    expect(s.view_style).toBe('dropdown')
    expect('open_in' in s).toBe(false)
  })
})
