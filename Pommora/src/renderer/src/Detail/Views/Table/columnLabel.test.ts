import { describe, it, expect } from 'vitest'
import { columnLabel, tierLabel } from './columnLabel'
import { DEFAULT_LABELS } from '@shared/types'
import { RESERVED_PROPERTY_ID, type PropertyDefinition } from '@shared/properties'

const labels = DEFAULT_LABELS
const schema: PropertyDefinition[] = [
  { id: 'prop_status', name: 'Status', type: 'status' },
  { id: 'prop_due', name: 'Due', type: 'datetime' },
]

describe('tierLabel', () => {
  it('maps tier levels to the per-Nexus plurals', () => {
    expect(tierLabel(1, labels)).toBe('Areas')
    expect(tierLabel(2, labels)).toBe('Topics')
    expect(tierLabel(3, labels)).toBe('Projects')
  })

  it('honors a custom tier label', () => {
    const custom = { ...labels, project: { singular: 'Initiative', plural: 'Initiatives' } }
    expect(tierLabel(3, custom)).toBe('Initiatives')
  })

  it('falls back to "Tier N" for an out-of-range level', () => {
    expect(tierLabel(0, labels)).toBe('Tier 0')
    expect(tierLabel(4, labels)).toBe('Tier 4')
  })
})

describe('columnLabel', () => {
  it('resolves reserved built-in columns', () => {
    expect(columnLabel(RESERVED_PROPERTY_ID.title, schema, labels)).toBe('Title')
    expect(columnLabel(RESERVED_PROPERTY_ID.createdAt, schema, labels)).toBe('Created')
    expect(columnLabel(RESERVED_PROPERTY_ID.modifiedAt, schema, labels)).toBe('Modified')
  })

  it('resolves tier columns through the labels', () => {
    expect(columnLabel(RESERVED_PROPERTY_ID.tier1, schema, labels)).toBe('Areas')
    expect(columnLabel(RESERVED_PROPERTY_ID.tier2, schema, labels)).toBe('Topics')
    expect(columnLabel(RESERVED_PROPERTY_ID.tier3, schema, labels)).toBe('Projects')
  })

  it('resolves a user property through the schema name', () => {
    expect(columnLabel('prop_status', schema, labels)).toBe('Status')
  })

  it('falls back to the id for an unknown column (never throws)', () => {
    expect(columnLabel('prop_gone', schema, labels)).toBe('prop_gone')
  })
})
