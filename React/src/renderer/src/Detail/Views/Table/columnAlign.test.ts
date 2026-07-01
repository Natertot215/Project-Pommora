import { describe, it, expect } from 'vitest'
import { alignFor, defaultAlignFor } from './columnAlign'
import { RESERVED_PROPERTY_ID, type PropertyDefinition } from '@shared/properties'
import { savedView, type SavedView } from '@shared/views'

const schema: PropertyDefinition[] = [
  { id: 'prop_status', name: 'Status', type: 'status' },
  { id: 'prop_multi', name: 'Tags', type: 'multi_select' },
  { id: 'prop_n', name: 'Count', type: 'number' },
  { id: 'prop_url', name: 'Link', type: 'url' }
]

function view(over: Partial<SavedView>): SavedView {
  return savedView.parse({ id: 'view_x', name: 'V', type: 'table', property_order: [], hidden_properties: [], ...over })
}

describe('defaultAlignFor', () => {
  it('centers the chip/box + context types (E-6)', () => {
    expect(defaultAlignFor('prop_status', schema)).toBe('center')
    expect(defaultAlignFor('prop_multi', schema)).toBe('center')
    expect(defaultAlignFor(RESERVED_PROPERTY_ID.tier1, schema)).toBe('center')
  })

  it('left-aligns title, number, url, and modified (E-6)', () => {
    expect(defaultAlignFor(RESERVED_PROPERTY_ID.title, schema)).toBe('left')
    expect(defaultAlignFor('prop_n', schema)).toBe('left')
    expect(defaultAlignFor('prop_url', schema)).toBe('left')
    expect(defaultAlignFor(RESERVED_PROPERTY_ID.modifiedAt, schema)).toBe('left')
  })

  it('falls back to left for an unknown column', () => {
    expect(defaultAlignFor('prop_gone', schema)).toBe('left')
  })
})

describe('alignFor', () => {
  it('uses the type default when no override is saved', () => {
    expect(alignFor('prop_status', schema, view({}))).toBe('center')
    expect(alignFor('prop_n', schema, view({}))).toBe('left')
  })

  it('honors a saved column_alignments override over the default', () => {
    const v = view({ column_alignments: { prop_status: 'left', prop_n: 'right' } })
    expect(alignFor('prop_status', schema, v)).toBe('left')
    expect(alignFor('prop_n', schema, v)).toBe('right')
  })
})
