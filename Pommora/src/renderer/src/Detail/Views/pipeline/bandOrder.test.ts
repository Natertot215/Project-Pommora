import { describe, it, expect } from 'vitest'
import type { ResolvedGroup } from '@shared/types'
import { orderGroups } from './bandOrder'

const sg = (key: string, children?: ResolvedGroup[]): ResolvedGroup => ({
  key,
  kind: 'structural-set',
  items: [],
  ...(children ? { children } : {}),
  isCollapsed: false
})
const ungrouped: ResolvedGroup = { key: '_ungrouped', kind: 'ungrouped', items: [], isCollapsed: false }
const prop = (key: string): ResolvedGroup => ({ key, kind: 'property', items: [], isCollapsed: false })
const keys = (gs: ResolvedGroup[]): string[] => gs.map((g) => g.key)

describe('orderGroups', () => {
  it('reorders top-level structural siblings by the flat array', () => {
    const groups = [sg('A'), sg('B'), sg('C'), ungrouped]
    expect(keys(orderGroups(groups, ['C', 'A', 'B']))).toEqual(['C', 'A', 'B', '_ungrouped'])
  })

  it('reorders nested siblings at every level from the same flat array', () => {
    const groups = [sg('A', [sg('A1'), sg('A2')]), sg('B')]
    const out = orderGroups(groups, ['B', 'A', 'A2', 'A1'])
    expect(keys(out)).toEqual(['B', 'A'])
    expect(keys(out[1].children ?? [])).toEqual(['A2', 'A1'])
  })

  it('keeps unlisted siblings in fs order after the listed ones', () => {
    const groups = [sg('A'), sg('B'), sg('C'), sg('D')]
    expect(keys(orderGroups(groups, ['D', 'B']))).toEqual(['D', 'B', 'A', 'C'])
  })

  it('pins ungrouped last even when the array names every set — or names ungrouped itself', () => {
    const groups = [sg('A'), sg('B'), ungrouped]
    expect(keys(orderGroups(groups, ['B', 'A']))).toEqual(['B', 'A', '_ungrouped'])
    expect(keys(orderGroups(groups, ['_ungrouped', 'B', 'A']))).toEqual(['B', 'A', '_ungrouped'])
  })

  it('leaves property groups untouched', () => {
    const groups = [prop('done'), prop('open'), ungrouped]
    expect(keys(orderGroups(groups, ['open', 'done']))).toEqual(['done', 'open', '_ungrouped'])
  })

  it('is identity for an undefined or empty order', () => {
    const groups = [sg('A'), sg('B')]
    expect(orderGroups(groups, undefined)).toBe(groups)
    expect(orderGroups(groups, [])).toBe(groups)
  })
})
