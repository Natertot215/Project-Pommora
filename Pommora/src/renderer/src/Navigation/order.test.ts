import { describe, it, expect } from 'vitest'
import { keyBetween } from './order'

describe('keyBetween', () => {
  it('seeds an empty list at 0', () => expect(keyBetween(null, null)).toBe(0))
  it('prepends below the first', () => expect(keyBetween(null, 0)).toBe(-1))
  it('appends above the last', () => expect(keyBetween(5, null)).toBe(6))
  it('takes the midpoint between two', () => expect(keyBetween(0, 1)).toBe(0.5))
  it('is strictly between its neighbors', () => {
    const m = keyBetween(0.5, 0.75)
    expect(m).toBeGreaterThan(0.5)
    expect(m).toBeLessThan(0.75)
  })
})
