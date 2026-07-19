import { describe, expect, it } from 'vitest'
import { bandShowsAdd } from './cardsBand'

describe('bandShowsAdd', () => {
  it('shows the add "+" on structural Set bands only', () => {
    expect(bandShowsAdd('structural-set')).toBe(true)
    expect(bandShowsAdd('property')).toBe(false)
    expect(bandShowsAdd('ungrouped')).toBe(false)
  })
})
