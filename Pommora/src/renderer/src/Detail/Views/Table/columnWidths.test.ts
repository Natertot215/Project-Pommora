import { describe, it, expect } from 'vitest'
import { clampWidth, widthFor } from './columnWidths'
import { RESERVED_PROPERTY_ID, type PropertyDefinition } from '@shared/properties'

const schema: PropertyDefinition[] = [
  { id: 'prop_status', name: 'Status', type: 'status' },
  { id: 'prop_n', name: 'Count', type: 'number' }
]

describe('widthFor', () => {
  it('keys reserved columns by their declared type', () => {
    expect(widthFor(RESERVED_PROPERTY_ID.title, schema).default).toBe(280)
    expect(widthFor(RESERVED_PROPERTY_ID.tier1, schema).default).toBe(140)
    expect(widthFor(RESERVED_PROPERTY_ID.modifiedAt, schema).default).toBe(120) // last_edited_time
    expect(widthFor(RESERVED_PROPERTY_ID.createdAt, schema).default).toBe(120) // special-cased
  })

  it('keys user properties by their schema type', () => {
    expect(widthFor('prop_status', schema)).toEqual({ min: 65, default: 120, max: 250 })
    expect(widthFor('prop_n', schema).default).toBe(100) // number
  })

  it('falls back for an unknown column', () => {
    expect(widthFor('prop_gone', schema)).toEqual({ min: 80, default: 140, max: Number.POSITIVE_INFINITY })
  })
})

describe('clampWidth', () => {
  it('clamps a resized width up to its min; the title grows uncapped, typed columns cap per-type', () => {
    expect(clampWidth(10, RESERVED_PROPERTY_ID.title, schema)).toBe(120) // below min still clamps up
    expect(clampWidth(9999, RESERVED_PROPERTY_ID.title, schema)).toBe(9999)
    expect(clampWidth(300, RESERVED_PROPERTY_ID.title, schema)).toBe(300) // in range
    expect(clampWidth(999, 'prop_status', schema)).toBe(250) // capped at the type's ceiling
  })
})
