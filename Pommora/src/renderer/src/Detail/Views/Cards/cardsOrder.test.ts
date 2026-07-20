import { describe, expect, it } from 'vitest'
import { reorderIds } from './cardsOrder'

describe('reorderIds', () => {
  it('moves the active id into the over id slot', () => {
    expect(reorderIds(['a', 'b', 'c'], 'a', 'c')).toEqual(['b', 'c', 'a'])
    expect(reorderIds(['a', 'b', 'c'], 'c', 'a')).toEqual(['c', 'a', 'b'])
  })
  it('returns a copy on a no-op (same id, or an absent id)', () => {
    expect(reorderIds(['a', 'b'], 'a', 'a')).toEqual(['a', 'b'])
    expect(reorderIds(['a', 'b'], 'z', 'a')).toEqual(['a', 'b'])
  })
})
