import { describe, it, expect } from 'vitest'
import { parseDefinitions, droppingUserContexts, validateName, validateDefinition } from './schema'
import type { PropertyDefinition } from '@shared/properties'

const def = (over: Partial<PropertyDefinition> & { id: string; name: string; type: PropertyDefinition['type'] }) =>
  over as PropertyDefinition

describe('parseDefinitions', () => {
  it('parses valid entries and drops malformed / retired-type ones', () => {
    const out = parseDefinitions([
      { id: 'p1', name: 'Score', type: 'number' },
      { id: 'p2', name: 'When', type: 'date' }, // retired type → fails the enum → dropped
      { name: 'missing id', type: 'number' }, // dropped
      'garbage' // dropped
    ])
    expect(out.map((d) => d.id)).toEqual(['p1'])
  })

  it('returns [] for non-array input', () => {
    expect(parseDefinitions(undefined)).toEqual([])
    expect(parseDefinitions({})).toEqual([])
  })
})

describe('droppingUserContexts', () => {
  it('drops user .context defs but keeps reserved tier contexts and non-contexts', () => {
    const out = droppingUserContexts([
      def({ id: 'prop_x', name: 'Link', type: 'context' }),
      def({ id: '_tier1', name: 'Areas', type: 'context' }),
      def({ id: 'prop_y', name: 'Score', type: 'number' })
    ])
    expect(out.map((d) => d.id)).toEqual(['_tier1', 'prop_y'])
  })
})

describe('validateName', () => {
  const existing = [def({ id: 'p1', name: 'Stage', type: 'status' })]

  it('rejects empty + case-insensitive duplicate names', () => {
    expect(validateName('   ', existing).ok).toBe(false)
    expect(validateName('stage', existing).ok).toBe(false)
  })

  it('allows the same name when it is the excluded def (rename no-op)', () => {
    expect(validateName('Stage', existing, 'p1').ok).toBe(true)
  })
})

describe('validateDefinition', () => {
  const existing = [def({ id: 'p1', name: 'Stage', type: 'status' })]

  it('blocks reserved ids and duplicate ids', () => {
    expect(validateDefinition(def({ id: '_status', name: 'X', type: 'number' }), existing).ok).toBe(false)
    expect(validateDefinition(def({ id: 'p1', name: 'New', type: 'number' }), existing).ok).toBe(false)
  })

  it('enforces select option constraints', () => {
    expect(validateDefinition(def({ id: 'p2', name: 'Tag', type: 'select' }), existing).ok).toBe(false)
    const dupOpts = def({
      id: 'p3',
      name: 'Tag2',
      type: 'select',
      select_options: [
        { value: 'a', label: 'A' },
        { value: 'a', label: 'A2' }
      ]
    })
    expect(validateDefinition(dupOpts, existing).ok).toBe(false)
  })

  it('accepts a valid new property', () => {
    expect(validateDefinition(def({ id: 'p9', name: 'Score', type: 'number' }), existing).ok).toBe(true)
  })
})
