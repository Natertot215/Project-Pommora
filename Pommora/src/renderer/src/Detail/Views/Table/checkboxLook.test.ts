import { describe, it, expect } from 'vitest'
import { checkboxBoxStyle } from './checkboxLook'

describe('checkboxBoxStyle', () => {
  it('unchecked → no fill, just the label-control check colour', () => {
    const s = checkboxBoxStyle(false, undefined)
    expect(s.background).toBeUndefined()
    expect(s.color).toBe('var(--label-control)')
  })

  it('colorless checked → tints var(--accent) so it matches the switch and resolves any accent setting', () => {
    expect(String(checkboxBoxStyle(true, undefined).background)).toContain('var(--accent)')
  })

  it('colored checked → tints the solid, check stays label-control', () => {
    const s = checkboxBoxStyle(true, 'blue')
    expect(String(s.background)).toContain('color-mix')
    expect(String(s.background)).not.toContain('var(--accent)')
    expect(s.color).toBe('var(--label-control)')
  })
})
