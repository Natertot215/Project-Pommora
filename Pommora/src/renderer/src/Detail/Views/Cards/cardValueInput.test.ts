import { describe, expect, it } from 'vitest'
import type { PropertyDefinition } from '@shared/properties'
import { orderAddableDefs, parseEditorValue } from './cardValueInput'

describe('parseEditorValue', () => {
  it('number: parses a finite value, trims, clears on empty, rejects garbage', () => {
    expect(parseEditorValue('number', '42')).toEqual({ kind: 'number', value: 42 })
    expect(parseEditorValue('number', '  3.5 ')).toEqual({ kind: 'number', value: 3.5 })
    expect(parseEditorValue('number', '')).toBeNull()
    expect(parseEditorValue('number', 'abc')).toBeUndefined()
  })

  it('url: normalizes + serializes a valid link, clears on empty, rejects invalid', () => {
    expect(parseEditorValue('url', 'example.com')).toEqual({
      kind: 'url',
      value: 'https://example.com',
    })
    expect(parseEditorValue('url', '')).toBeNull()
    expect(parseEditorValue('url', 'not a url')).toBeUndefined()
  })

  it('an unsupported type never commits', () => {
    expect(parseEditorValue('status', 'x')).toBeUndefined()
  })
})

describe('orderAddableDefs', () => {
  it('sinks the chevron-less checkbox to the bottom; every pane (chevron) kind stays on top in property order', () => {
    const defs = [
      { id: 'n', type: 'number', name: 'N' },
      { id: 'chk', type: 'checkbox', name: 'Chk' },
      { id: 's', type: 'status', name: 'S' },
      { id: 'd', type: 'datetime', name: 'D' },
      { id: 'u', type: 'url', name: 'U' },
    ] as PropertyDefinition[]
    // number/status/datetime/url all open a value pane (chevron) → top, property order kept; checkbox last.
    expect(orderAddableDefs(defs).map((d) => d.id)).toEqual(['n', 's', 'd', 'u', 'chk'])
  })
})
