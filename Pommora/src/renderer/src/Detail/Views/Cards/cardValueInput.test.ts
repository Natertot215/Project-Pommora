import { describe, expect, it } from 'vitest'
import { type AddEntry, orderAddableEntries, parseEditorValue } from './cardValueInput'

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

describe('orderAddableEntries', () => {
  it('sinks reveal-only entries to the bottom; pane entries stay on top in order', () => {
    const entries: AddEntry[] = [
      { id: 'n', name: 'N', type: 'number', def: null, revealOnly: false },
      { id: 'chk', name: 'Chk', type: 'checkbox', def: null, revealOnly: true },
      { id: 's', name: 'S', type: 'status', def: null, revealOnly: false },
      { id: 'area', name: 'Areas', type: 'context', def: null, revealOnly: true },
      { id: 'u', name: 'U', type: 'url', def: null, revealOnly: false },
    ]
    expect(orderAddableEntries(entries).map((e) => e.id)).toEqual(['n', 's', 'u', 'chk', 'area'])
  })
})
