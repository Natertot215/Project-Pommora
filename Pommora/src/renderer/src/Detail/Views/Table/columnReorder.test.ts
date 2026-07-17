import { describe, it, expect } from 'vitest'
import { reorderColumns } from './columnReorder'

describe('reorderColumns', () => {
  it('moves a visible column to a new slot, writing the full explicit order', () => {
    expect(reorderColumns(['_title', 'a', 'b', 'c'], ['_title', 'a', 'b', 'c'], 'c', 'a')).toEqual([
      '_title',
      'c',
      'a',
      'b',
    ])
  })

  it('preserves a hidden property (in property_order, not rendered) at the tail — survives hide/show (H-2)', () => {
    expect(reorderColumns(['_title', 'a'], ['_title', 'hidden1', 'a'], 'a', '_title')).toEqual([
      'a',
      '_title',
      'hidden1',
    ])
  })

  it('writes default-on tier/title columns explicitly even when absent from property_order', () => {
    expect(reorderColumns(['_title', '_tier1'], [], '_tier1', '_title')).toEqual([
      '_tier1',
      '_title',
    ])
  })

  it('normalizes (visible + hidden) without moving when active === over', () => {
    expect(reorderColumns(['_title', 'a'], ['_title', 'a', 'hidden1'], 'a', 'a')).toEqual([
      '_title',
      'a',
      'hidden1',
    ])
  })
})
