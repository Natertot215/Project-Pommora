import { describe, expect, it } from 'vitest'
import { DEFAULT_ITEMS, isSubfieldItemId } from './subfieldItems'

describe('subfield item registry', () => {
  it('recognizes viewType and rejects unknown ids', () => {
    expect(isSubfieldItemId('viewType')).toBe(true)
    expect(isSubfieldItemId('pageStats')).toBe(true)
    expect(isSubfieldItemId('nope')).toBe(false)
  })

  it('NavView (the none kind) defaults to the viewType toggle', () => {
    expect(DEFAULT_ITEMS.none).toEqual(['viewType'])
  })
})
