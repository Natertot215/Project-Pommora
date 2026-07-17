import { describe, it, expect } from 'vitest'
import { mergeTierProperties } from './tiers'
import type { PropertyDefinition } from '@shared/properties'

const def = (
  over: Partial<PropertyDefinition> & {
    id: string
    name: string
    type: PropertyDefinition['type']
  },
) => over as PropertyDefinition

describe('mergeTierProperties', () => {
  it('appends the three tier props after user props, with locked context_tier targets', () => {
    const out = mergeTierProperties([def({ id: 'prop_x', name: 'Score', type: 'number' })])
    expect(out.map((d) => d.id)).toEqual(['prop_x', '_tier1', '_tier2', '_tier3'])
    expect(out.every((d, i) => (i === 0 ? true : d.type === 'context'))).toBe(true)
    expect(out[1].context_target).toEqual({ kind: 'context_tier', tier: 1 })
    expect(out[3].context_target).toEqual({ kind: 'context_tier', tier: 3 })
  })

  it('names tiers from tierPlural, falling back to "Tier N"', () => {
    const out = mergeTierProperties([], (level) => (level === 1 ? 'Areas' : undefined))
    expect(out.map((d) => d.name)).toEqual(['Areas', 'Tier 2', 'Tier 3'])
    expect(out[0].icon).toBe('square.grid.2x2')
  })

  it('honors a sidecar override entry (name/icon/reverse) and never duplicates it', () => {
    const out = mergeTierProperties([
      def({
        id: '_tier1',
        name: 'My Areas',
        type: 'context',
        icon: 'star',
        reverse_name: 'Pages',
        reverse_icon: 'doc',
      }),
    ])
    expect(out.map((d) => d.id)).toEqual(['_tier1', '_tier2', '_tier3'])
    expect(out[0]).toMatchObject({
      name: 'My Areas',
      icon: 'star',
      reverse_name: 'Pages',
      reverse_icon: 'doc',
      context_target: { kind: 'context_tier', tier: 1 },
    })
  })

  it('keeps a reserved _modified_at override among the user props', () => {
    const out = mergeTierProperties([
      def({ id: '_modified_at', name: 'Modified', type: 'last_edited_time' }),
    ])
    expect(out.map((d) => d.id)).toEqual(['_modified_at', '_tier1', '_tier2', '_tier3'])
  })
})
