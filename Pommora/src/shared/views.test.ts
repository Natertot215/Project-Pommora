import { describe, it, expect } from 'vitest'
import fixture from './__fixtures__/collection-with-status.json'
import { savedView, decodeGroupConfig, decodeSubGroup, mintDefaultView, mintNewView, type FilterGroup, type FilterRule } from './views'
import { pageCollectionSidecar } from './schemas'
import { RESERVED_PROPERTY_ID } from './properties'

describe('SavedView decode', () => {
  it('parses the fixture Table view (type, property_order, group, sort)', () => {
    const v = savedView.parse(fixture.views[0])
    expect(v.type).toBe('table')
    expect(v.property_order[0]).toBe('prop_status')
    expect(v.group).toEqual({
      kind: 'property',
      property_id: 'prop_status',
      order_mode: 'manual',
      order: ['in_progress', 'opt_open', 'not_started', 'done'],
      empty_placement: 'bottom',
      hide_empty_groups: false
    })
    expect(v.sort).toEqual([{ property_id: 'prop_status', direction: 'descending' }])
  })

  it('preserves a foreign key on the view object (looseObject)', () => {
    const v = savedView.parse(fixture.views[0]) as Record<string, unknown>
    expect(v._foreign_view_key).toBe('preserved')
  })

  it('round-trips the hide_page_icons / hide_borders display toggles', () => {
    const v = savedView.parse({
      id: 'view_z',
      name: 'Z',
      type: 'table',
      property_order: [],
      hidden_properties: [],
      hide_page_icons: true,
      hide_borders: true
    })
    expect(v.hide_page_icons).toBe(true)
    expect(v.hide_borders).toBe(true)
  })

  it('falls an unknown group.kind back to structural', () => {
    const v = savedView.parse({
      id: 'view_x',
      name: 'X',
      type: 'table',
      property_order: [],
      hidden_properties: [],
      group: { kind: 'galaxy', property_id: 'p' }
    })
    expect(v.group).toEqual({ kind: 'structural' })
  })

  it('decodes a legacy bare {property_id} group to property WITH injected defaults', () => {
    const v = savedView.parse({
      id: 'view_y',
      name: 'Y',
      type: 'table',
      property_order: [],
      hidden_properties: [],
      group: { property_id: 'p' }
    })
    expect(v.group).toEqual({
      kind: 'property',
      property_id: 'p',
      order_mode: 'configured',
      empty_placement: 'bottom',
      hide_empty_groups: false
    })
  })

  it('round-trips group_order and drops non-string entries alone (element-filtering, not whole-array catch)', () => {
    const base = { id: 'view_g', name: 'G', type: 'table', property_order: [], hidden_properties: [] }
    expect(savedView.parse({ ...base, group_order: ['s1', 's2'] }).group_order).toEqual(['s1', 's2'])
    expect(savedView.parse({ ...base, group_order: ['s1', 42, 's2'] }).group_order).toEqual(['s1', 's2'])
    expect(savedView.parse(base).group_order).toBeUndefined()
  })

  it('coerces a non-array group_order to empty instead of crashing', () => {
    const v = savedView.parse({
      id: 'view_g',
      name: 'G',
      type: 'table',
      property_order: [],
      hidden_properties: [],
      group_order: 'nonsense'
    })
    expect(v.group_order).toEqual([])
  })

  it('wires a typed views[] into the collection sidecar schema', () => {
    const parsed = pageCollectionSidecar.parse(fixture)
    expect(parsed.views?.[0].type).toBe('table')
    expect(parsed.views?.[0].group).toMatchObject({ kind: 'property', order_mode: 'manual' })
  })
})

describe('sort criterion custom order', () => {
  const base = { id: 'view_s', name: 'S', type: 'table', property_order: [], hidden_properties: [] }
  it('round-trips a criterion order array and leaves it absent otherwise', () => {
    const v = savedView.parse({
      ...base,
      sort: [
        { property_id: 'p1', direction: 'ascending', order: ['a', 'b'] },
        { property_id: 'p2', direction: 'descending' }
      ]
    })
    expect(v.sort?.[0].order).toEqual(['a', 'b'])
    expect(v.sort?.[1].order).toBeUndefined()
  })
})

describe('view-level grouping fields', () => {
  const base = { id: 'view_x', name: 'T', type: 'table', property_order: [], hidden_properties: [] }
  it('savedView round-trips all four fields', () => {
    const v = savedView.parse({
      ...base,
      structural_order_mode: 'location',
      ungrouped_placement: 'top',
      date_separator: 'slash',
      sub_group: { property_id: 'p1', order_mode: 'manual', order: ['a', 'b'], date_granularity: 'week' }
    })
    expect(v.structural_order_mode).toBe('location')
    expect(v.ungrouped_placement).toBe('top')
    expect(v.date_separator).toBe('slash')
    expect(v.sub_group).toEqual({ property_id: 'p1', order_mode: 'manual', order: ['a', 'b'], date_granularity: 'week' })
  })
  it('a legacy view decodes with all four absent', () => {
    const v = savedView.parse(base)
    expect(v.structural_order_mode).toBeUndefined()
    expect(v.sub_group).toBeUndefined()
    expect(v.ungrouped_placement).toBeUndefined()
    expect(v.date_separator).toBeUndefined()
  })
  it('malformed fields drop without poisoning the view', () => {
    const v = savedView.parse({ ...base, structural_order_mode: 'nope', sub_group: { order_mode: 'manual' } })
    expect(v.structural_order_mode).toBeUndefined()
    expect(v.sub_group).toBeUndefined()
  })
  it('decodeSubGroup fills order_mode and filters non-string order entries', () => {
    expect(decodeSubGroup({ property_id: 'p1', order: ['a', 7, 'b'] })).toEqual({
      property_id: 'p1',
      order_mode: 'configured',
      order: ['a', 'b']
    })
  })
})

describe('decodeGroupConfig (lenient, mirrors Swift)', () => {
  it('passes structural and flat through', () => {
    expect(decodeGroupConfig({ kind: 'structural' })).toEqual({ kind: 'structural' })
    expect(decodeGroupConfig({ kind: 'flat' })).toEqual({ kind: 'flat' })
  })

  it('degrades garbage / null / non-object to structural', () => {
    expect(decodeGroupConfig(null)).toEqual({ kind: 'structural' })
    expect(decodeGroupConfig('nope')).toEqual({ kind: 'structural' })
    expect(decodeGroupConfig([])).toEqual({ kind: 'structural' })
    expect(decodeGroupConfig({})).toEqual({ kind: 'structural' })
  })
})

describe('SavedView format', () => {
  const base = { id: 'view_x', name: 'B', property_order: [], hidden_properties: [] }
  it('coerces an unknown type to table and round-trips a valid format', () => {
    const v = savedView.parse({ ...base, type: 'board', format: 'compact' })
    expect(v.type).toBe('table')
    expect(v.format).toBe('compact')
  })
  it('drops an unknown format value', () => {
    const v = savedView.parse({ ...base, type: 'table', format: 'huge' })
    expect(v.format).toBeUndefined()
  })
})

describe('mint seam', () => {
  const schema = [{ id: 'prop_a' }, { id: 'prop_b' }] as never[]
  it('mintNewView is title-only: schema ids and all three tiers hidden', () => {
    const v = mintNewView('Untitled', schema)
    expect(v.name).toBe('Untitled')
    expect(v.type).toBe('table')
    expect(v.icon).toBe('table')
    expect(v.property_order).toEqual([RESERVED_PROPERTY_ID.title])
    expect(v.hidden_properties).toEqual([
      'prop_a',
      'prop_b',
      RESERVED_PROPERTY_ID.tier1,
      RESERVED_PROPERTY_ID.tier2,
      RESERVED_PROPERTY_ID.tier3
    ])
  })
  it('mintDefaultView stays all-shown with the table glyph', () => {
    const v = mintDefaultView(schema)
    expect(v.hidden_properties).toEqual([])
    expect(v.property_order).toEqual([RESERVED_PROPERTY_ID.title, 'prop_a', 'prop_b'])
    expect(v.icon).toBe('table')
  })
})

describe('filter codec', () => {
  it('round-trips a filter with values[], match none, and nesting', () => {
    const view = savedView.parse({
      id: 'view_x',
      name: 'T',
      type: 'table',
      property_order: [],
      hidden_properties: [],
      filter: {
        match: 'none',
        rules: [
          {
            match: 'any',
            rules: [
              { property_id: 'prop_tags', op: 'contains_any', values: ['a', 'b'] },
              { match: 'all', rules: [{ property_id: 'prop_sel', op: 'is', value: 'x' }] }
            ]
          }
        ]
      }
    })
    const group = view.filter as FilterGroup
    expect(group.match).toBe('none')
    const inner = group.rules[0] as FilterGroup
    expect(inner.match).toBe('any')
    expect((inner.rules[0] as FilterRule).values).toEqual(['a', 'b'])
  })
})
