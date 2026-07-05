import { describe, it, expect } from 'vitest'
import { autocompleteQuery, connectionInsert } from './autocomplete'

describe('autocompleteQuery', () => {
  it('detects a non-empty query with the caret inside the brackets', () => {
    const doc = 'see [[Pro]] end'
    const r = autocompleteQuery(doc, 9)! // caret after "Pro"
    expect(r.query).toBe('Pro')
    expect(doc.slice(r.from, r.to)).toBe('[[Pro]]')
  })
  it('suppresses on an empty placeholder', () => {
    expect(autocompleteQuery('see [[]] end', 6)).toBeNull()
  })
  it('suppresses image embeds ![[…]]', () => {
    expect(autocompleteQuery('see ![[Pic]] end', 9)).toBeNull()
  })
  it('returns null when the caret is outside any wikilink', () => {
    expect(autocompleteQuery('plain text', 5)).toBeNull()
    expect(autocompleteQuery('[[Pro]] x', 9)).toBeNull() // caret past the closer
  })
})

describe('connectionInsert', () => {
  it('builds [[Title]] and the caret after the closer', () => {
    const { insert, caret } = connectionInsert('Page A', 4)
    expect(insert).toBe('[[Page A]]')
    expect(caret).toBe(4 + '[[Page A]]'.length)
  })
})
