import { describe, it, expect } from 'vitest'
import fixture from './__fixtures__/collection-with-status.json'
import { savedView, decodeGroupConfig } from './views'
import { pageCollectionSidecar } from './schemas'

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
