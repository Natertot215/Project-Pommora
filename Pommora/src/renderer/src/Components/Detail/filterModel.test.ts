import { describe, expect, it } from 'vitest'
import type { PropertyDefinition } from '@shared/properties'
import { decodeFilter, encodeFilter, filterTargets, operatorsFor } from './filterModel'

const r = (id: string, op = 'is', value = 'x'): { property_id: string; op: string; value: string } => ({
  property_id: id,
  op,
  value
})

describe('encodeFilter', () => {
  it('all-and → flat all group', () => {
    expect(
      encodeFilter(true, [
        { connector: null, rule: r('a') },
        { connector: 'and', rule: r('b') }
      ])
    ).toEqual({ match: 'all', rules: [r('a'), r('b')] })
  })

  it('A and B, or C → any of [all-run, leaf]', () => {
    expect(
      encodeFilter(true, [
        { connector: null, rule: r('a') },
        { connector: 'and', rule: r('b') },
        { connector: 'or', rule: r('c') }
      ])
    ).toEqual({ match: 'any', rules: [{ match: 'all', rules: [r('a'), r('b')] }, r('c')] })
  })

  it('no rows enabled → undefined; disabled wraps losslessly', () => {
    expect(encodeFilter(true, [])).toBeUndefined()
    expect(encodeFilter(false, [{ connector: null, rule: r('a') }])).toEqual({
      match: 'none',
      rules: [{ match: 'all', rules: [r('a')] }]
    })
    expect(encodeFilter(false, [])).toEqual({ match: 'none', rules: [] })
  })
})

describe('decodeFilter', () => {
  it('round-trips every editable shape bit-identically', () => {
    const shapes = [
      encodeFilter(true, [{ connector: null, rule: r('a') }]),
      encodeFilter(true, [
        { connector: null, rule: r('a') },
        { connector: 'or', rule: r('b') }
      ]),
      encodeFilter(true, [
        { connector: null, rule: r('a') },
        { connector: 'and', rule: r('b') },
        { connector: 'or', rule: r('c') }
      ]),
      encodeFilter(false, [
        { connector: null, rule: r('a') },
        { connector: 'or', rule: r('b') }
      ])
    ]
    for (const tree of shapes) {
      const d = decodeFilter(tree)
      expect(d.kind).toBe('rows')
      if (d.kind === 'rows') expect(encodeFilter(d.enabled, d.rows)).toEqual(tree)
    }
  })

  it('mixed connectors read mode all; pure or reads any (D-10)', () => {
    const mixed = decodeFilter({ match: 'any', rules: [{ match: 'all', rules: [r('a'), r('b')] }, r('c')] })
    expect(mixed.kind === 'rows' && mixed.mode).toBe('all')
    const pureOr = decodeFilter({ match: 'any', rules: [r('a'), r('b')] })
    expect(pureOr.kind === 'rows' && pureOr.mode).toBe('any')
  })

  it('locks the shallow trap: an any nested under an all root', () => {
    expect(decodeFilter({ match: 'all', rules: [r('a'), { match: 'any', rules: [r('b'), r('c')] }] }).kind).toBe('locked')
  })

  it('locks 3-deep nesting', () => {
    expect(
      decodeFilter({ match: 'any', rules: [{ match: 'all', rules: [r('a'), { match: 'any', rules: [r('b')] }] }] }).kind
    ).toBe('locked')
  })

  it('a hand-authored none with leaf children is locked-disabled', () => {
    const d = decodeFilter({ match: 'none', rules: [r('a'), r('b')] })
    expect(d.kind).toBe('locked')
    expect(d.enabled).toBe(false)
  })

  it('undefined → enabled empty rows', () => {
    expect(decodeFilter(undefined)).toEqual({ kind: 'rows', enabled: true, mode: 'all', rows: [] })
  })
})

describe('vocabulary', () => {
  const schema: PropertyDefinition[] = [
    { id: 'prop_sel', name: 'Sel', type: 'select' },
    { id: 'prop_done', name: 'Done', type: 'checkbox' },
    { id: 'prop_tags', name: 'Tags', type: 'multi_select' }
  ]

  it('checkbox operators carry the whole clause (slot none, implied values)', () => {
    const ops = operatorsFor('prop_done', schema)
    expect(ops.map((o) => o.label)).toEqual(['Is Checked', "Isn't Checked"])
    expect(ops.every((o) => o.slot === 'none')).toBe(true)
    expect(ops.map((o) => o.impliedValue)).toEqual(['true', 'false'])
  })

  it("select reads Is / Isn't / Is Empty / Isn't Empty with chip slots on the membership ops", () => {
    const ops = operatorsFor('prop_sel', schema)
    expect(ops.map((o) => o.label)).toEqual(['Is', "Isn't", 'Is Empty', "Isn't Empty"])
    expect(ops[0].slot).toBe('chips')
    expect(ops[0].multi).toBe(true)
    expect(ops[2].slot).toBe('none')
  })

  it('multi-select reads Is Any / Is All / Isn\'t + empties', () => {
    expect(operatorsFor('prop_tags', schema).map((o) => o.op)).toEqual([
      'contains_any',
      'contains_all',
      'does_not_contain',
      'is_empty',
      'is_not_empty'
    ])
  })

  it('targets lead Title · Location · Modified · tiers, then schema', () => {
    expect(filterTargets(schema).map((t) => t.label)).toEqual([
      'Title',
      'Location',
      'Modified',
      'Areas',
      'Topics',
      'Projects',
      'Sel',
      'Done',
      'Tags'
    ])
  })
})
