import { describe, it, expect } from 'vitest'
import fixture from './__fixtures__/collection-with-status.json'
import { savedView, decodeGroupConfig, mintDefaultView, mintNewView } from './views'
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
