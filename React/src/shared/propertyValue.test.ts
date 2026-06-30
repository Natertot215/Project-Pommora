import { describe, it, expect } from 'vitest'
import { parsePropertyValue, encodePropertyValue, type PropertyValue } from './propertyValue'

describe('parsePropertyValue — classification (locked precedence)', () => {
  const cases: Array<[string, unknown, PropertyValue]> = [
    ['null', null, { kind: 'null' }],
    ['bool true', true, { kind: 'checkbox', value: true }],
    ['bool false', false, { kind: 'checkbox', value: false }],
    ['number', 42, { kind: 'number', value: 42 }],
    ['number zero', 0, { kind: 'number', value: 0 }],
    ['context (multi)', [{ $ctx: 'A' }, { $ctx: 'B' }], { kind: 'context', value: ['A', 'B'] }],
    ['context (single in array)', [{ $ctx: 'A' }], { kind: 'context', value: ['A'] }],
    [
      'file',
      [{ path: 'x/y.png', original_name: 'y.png' }],
      { kind: 'file', value: [{ path: 'x/y.png', original_name: 'y.png' }] }
    ],
    ['multiSelect', ['a', 'b'], { kind: 'multiSelect', value: ['a', 'b'] }],
    ['empty array → multiSelect([]) (NOT file)', [], { kind: 'multiSelect', value: [] }],
    ['status (tagged)', { $status: 'todo' }, { kind: 'status', value: 'todo' }],
    ['single $ctx object', { $ctx: 'A' }, { kind: 'context', value: ['A'] }],
    ['url', 'https://example.com', { kind: 'url', value: 'https://example.com' }],
    ['datetime', '2026-01-15T10:30:00Z', { kind: 'datetime', value: '2026-01-15T10:30:00Z' }],
    ['datetime offset', '2026-01-15T10:30:00+02:00', { kind: 'datetime', value: '2026-01-15T10:30:00+02:00' }],
    ['bare date → date-only datetime', '2026-01-15', { kind: 'datetime', value: '2026-01-15' }],
    ['select (plain string)', 'in-progress', { kind: 'select', value: 'in-progress' }],
    ['select (datetime w/o tz falls through)', '2026-01-15T10:30:00', { kind: 'select', value: '2026-01-15T10:30:00' }]
  ]
  for (const [name, raw, expected] of cases) {
    it(name, () => expect(parsePropertyValue(raw)).toEqual(expected))
  }
})

describe('round-trip — encode(parse(x)) === x for canonical on-disk shapes', () => {
  const canonical: unknown[] = [
    null,
    true,
    false,
    42,
    0,
    [{ $ctx: 'A' }, { $ctx: 'B' }],
    [{ path: 'x/y.png', original_name: 'y.png', added_at: '2026-01-01T00:00:00Z', mime_type: 'image/png' }],
    ['a', 'b'],
    [],
    { $status: 'todo' },
    'https://example.com',
    '2026-01-15T10:30:00Z',
    '2026-01-15',
    'in-progress'
  ]
  for (const value of canonical) {
    it(JSON.stringify(value), () => expect(encodePropertyValue(parsePropertyValue(value))).toEqual(value))
  }
})

describe('edges + invariants', () => {
  it('a single $ctx normalizes to a tagged array on re-encode', () => {
    expect(encodePropertyValue(parsePropertyValue({ $ctx: 'A' }))).toEqual([{ $ctx: 'A' }])
  })

  it('file objects preserve unknown keys through a round-trip', () => {
    const raw = [{ path: 'a.png', foreign_key: 'kept' }]
    expect(encodePropertyValue(parsePropertyValue(raw))).toEqual(raw)
  })

  it('a mixed array throws (matches Swift)', () => {
    expect(() => parsePropertyValue([{ $ctx: 'A' }, { path: 'b' }])).toThrow()
    expect(() => parsePropertyValue([1, 'a'])).toThrow()
  })

  it('encoding lastEditedTime throws (virtual, never persisted)', () => {
    expect(() => encodePropertyValue({ kind: 'lastEditedTime' })).toThrow()
  })
})
