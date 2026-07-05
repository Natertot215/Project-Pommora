import { describe, it, expect } from 'vitest'
import fixture from '@shared/__fixtures__/collection-with-status.json'
import registry from '@shared/__fixtures__/registry.json'
import { savedView, type SavedView } from '@shared/views'
import { propertyDefinition, type PropertyDefinition } from '@shared/properties'
import { resolveColumns } from './columns'

const schema: PropertyDefinition[] = [
  { id: 'prop_a', name: 'A', type: 'select' },
  { id: 'prop_b', name: 'B', type: 'number' }
]

function view(over: Partial<SavedView>): SavedView {
  return { id: 'v', name: 'V', type: 'table', property_order: [], hidden_properties: [], ...over }
}

const ids = (cols: { id: string }[]): string[] => cols.map((c) => c.id)

describe('resolveColumns — fixture', () => {
  it('emits propertyOrder verbatim, appends unaccounted props, no _modified_at default-on', () => {
    const v = savedView.parse(fixture.views[0])
    const fixtureSchema = fixture.properties.map((id) =>
      propertyDefinition.parse((registry as Record<string, unknown>)[id])
    )
    const cols = resolveColumns(v, fixtureSchema)
    expect(ids(cols)).toEqual(['prop_status', '_title', '_tier3', '_tier2', '_tier1', 'prop_when'])
    expect(cols.map((c) => c.kind)).toEqual(['property', 'title', 'tier', 'tier', 'tier', 'property'])
    // fixture hides _modified_at and it is not default-on → never a column
    expect(cols.some((c) => c.id === '_modified_at')).toBe(false)
  })
})

describe('resolveColumns — rules', () => {
  it('appends default-on tiers when not placed; _modified_at is NOT default-on (React divergence)', () => {
    const cols = resolveColumns(view({ property_order: ['_title'] }), schema)
    expect(ids(cols)).toEqual(['_title', 'prop_a', 'prop_b', '_tier3', '_tier2', '_tier1'])
    expect(cols.some((c) => c.id === '_modified_at')).toBe(false)
  })

  it('renders _modified_at only when explicitly placed (def-less, kind modified)', () => {
    const cols = resolveColumns(view({ property_order: ['_title', '_modified_at'] }), schema)
    expect(ids(cols)).toEqual(['_title', '_modified_at', 'prop_a', 'prop_b', '_tier3', '_tier2', '_tier1'])
    expect(cols.find((c) => c.id === '_modified_at')?.kind).toBe('modified')
  })

  it('excludes a hidden property, but never hides _title (front-inserted)', () => {
    const cols = resolveColumns(
      view({ property_order: ['_title', 'prop_a'], hidden_properties: ['prop_a', '_title'] }),
      schema
    )
    expect(ids(cols)).toEqual(['_title', 'prop_b', '_tier3', '_tier2', '_tier1'])
  })

  it('front-inserts Title when propertyOrder omits it', () => {
    const cols = resolveColumns(view({ property_order: ['prop_a'] }), schema)
    expect(cols[0]).toEqual({ id: '_title', kind: 'title' })
  })

  it('skips a stale propertyOrder id absent from the schema', () => {
    const cols = resolveColumns(view({ property_order: ['_title', 'prop_ghost'] }), schema)
    expect(cols.some((c) => c.id === 'prop_ghost')).toBe(false)
  })

  it('maps each column id to its kind', () => {
    const cols = resolveColumns(view({ property_order: ['_title', '_tier1', 'prop_a', '_modified_at'] }), schema)
    const kindOf = (id: string): string | undefined => cols.find((c) => c.id === id)?.kind
    expect(kindOf('_title')).toBe('title')
    expect(kindOf('_tier1')).toBe('tier')
    expect(kindOf('prop_a')).toBe('property')
    expect(kindOf('_modified_at')).toBe('modified')
  })
})
