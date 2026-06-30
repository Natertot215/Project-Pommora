import { describe, it, expect } from 'vitest'
import {
  propertyDefinition,
  propertyType,
  isReservedPropertyId,
  tierPropertyId,
  tierFieldName,
  defaultStatusSeed,
  RESERVED_PROPERTY_ID
} from './properties'

describe('propertyType', () => {
  it('accepts the 10 on-disk type strings', () => {
    for (const t of [
      'number',
      'checkbox',
      'datetime',
      'select',
      'multi_select',
      'status',
      'url',
      'context',
      'last_edited_time',
      'file'
    ]) {
      expect(propertyType.safeParse(t).success).toBe(true)
    }
  })

  it('rejects an unknown type', () => {
    expect(propertyType.safeParse('rich_text').success).toBe(false)
  })
})

describe('propertyDefinition', () => {
  it('round-trips a fully-specified def and preserves a foreign key', () => {
    const def = {
      id: 'prop_01H',
      name: 'Stage',
      type: 'status',
      icon: 'circle',
      status_groups: defaultStatusSeed(),
      reverse_name: 'Stages',
      // foreign / display-config keys ride through (looseObject)
      display_as: 'pill',
      plugin_meta: { keep: true }
    }
    const parsed = propertyDefinition.parse(def)
    expect(parsed).toEqual(def)
  })

  it('parses a tier override entry (reserved id + context_tier target)', () => {
    const def = {
      id: RESERVED_PROPERTY_ID.tier1,
      name: 'Areas',
      type: 'context',
      context_target: { kind: 'context_tier', tier: 1 }
    }
    expect(propertyDefinition.safeParse(def).success).toBe(true)
  })

  it('requires id, name, and a valid type', () => {
    expect(propertyDefinition.safeParse({ name: 'x', type: 'number' }).success).toBe(false)
    expect(propertyDefinition.safeParse({ id: 'p', type: 'number' }).success).toBe(false)
    expect(propertyDefinition.safeParse({ id: 'p', name: 'x', type: 'nope' }).success).toBe(false)
  })
})

describe('reserved property ids', () => {
  it('recognizes reserved vs user ids', () => {
    expect(isReservedPropertyId('_status')).toBe(true)
    expect(isReservedPropertyId('_tier1')).toBe(true)
    expect(isReservedPropertyId('prop_01H')).toBe(false)
    expect(isReservedPropertyId('stage')).toBe(false)
  })

  it('maps a tier level to its reserved id and its bare root field', () => {
    expect(tierPropertyId(1)).toBe('_tier1')
    expect(tierPropertyId(3)).toBe('_tier3')
    expect(tierFieldName(1)).toBe('tier1')
    expect(tierFieldName(3)).toBe('tier3')
  })
})

describe('defaultStatusSeed', () => {
  it('seeds the three fixed groups with their starter options', () => {
    const seed = defaultStatusSeed()
    expect(seed.map((g) => g.id)).toEqual(['upcoming', 'in_progress', 'done'])
    expect(seed[0].options[0].value).toBe('not_started')
    expect(seed[2].options[0]).toMatchObject({ value: 'done', group_id: 'done' })
  })
})
