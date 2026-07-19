import { describe, expect, it } from 'vitest'
import { reorderIds, resolveManualOrder } from './cardsOrder'

describe('resolveManualOrder', () => {
  it('returns undefined for a plain view (unsorted, ungrouped, no active drag)', () => {
    expect(resolveManualOrder(false, null, ['a', 'b'])).toBeUndefined()
    expect(resolveManualOrder(false, null, undefined)).toBeUndefined()
  })

  it('an active drag override wins even on a plain view (instant drop feedback)', () => {
    expect(resolveManualOrder(false, ['x', 'y'], ['a', 'b'])).toEqual(['x', 'y'])
  })

  it('reads the persisted per-view order when the view is sorted or grouped', () => {
    expect(resolveManualOrder(true, null, ['a', 'b'])).toEqual(['a', 'b'])
    expect(resolveManualOrder(true, null, undefined)).toBeUndefined()
  })

  it('the override still wins over the persisted order when sorted', () => {
    expect(resolveManualOrder(true, ['x'], ['a', 'b'])).toEqual(['x'])
  })
})

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
