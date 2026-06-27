import { describe, it, expect } from 'vitest'
import { EditorState } from '@codemirror/state'
import { stripsCalloutPrefix, calloutGuard } from './calloutGuard'

describe('calloutGuard — stripsCalloutPrefix (body prefix is uncorruptible)', () => {
  const doc = '> [!callout] head\n> body' // body line starts at 18, its `> ` prefix is [18, 20)

  it('blocks deleting the whole body `> ` in place (the atomic-expanded delete)', () => {
    expect(stripsCalloutPrefix(doc, 18, 20)).toBe(true)
  })
  it('blocks deleting just the space (the `>body` corruption)', () => {
    expect(stripsCalloutPrefix(doc, 19, 20)).toBe(true)
  })
  it('ALLOWS a join — a delete reaching back past the line start (merges into the callout above)', () => {
    expect(stripsCalloutPrefix(doc, 17, 20)).toBe(false) // deletes `\n> `
  })
  it('ALLOWS deleting content after the prefix', () => {
    expect(stripsCalloutPrefix(doc, 20, 24)).toBe(false) // deletes "body"
  })
  it('ALLOWS stripping the HEAD prefix (intentional de-callout of the whole box)', () => {
    expect(stripsCalloutPrefix(doc, 0, 13)).toBe(false) // `> [!callout] `
  })
  it('is a no-op for inserts (to <= from)', () => {
    expect(stripsCalloutPrefix(doc, 20, 20)).toBe(false)
  })
  it('ignores non-callout quotes (a plain `> ` quote can still be de-quoted normally)', () => {
    const q = '> a plain quote'
    expect(stripsCalloutPrefix(q, 0, 2)).toBe(false)
  })
})

// Proves the wired extension actually CANCELS the transaction (not just that the logic returns true). Runs on a
// bare EditorState — no DOM — so it exercises the real transactionFilter end-to-end.
describe('calloutGuard — the wired filter cancels prefix-stripping transactions', () => {
  const doc = '> [!callout] head\n> body'
  const del = (from: number, to: number): string => {
    const state = EditorState.create({ doc, extensions: [calloutGuard] })
    return state.update({ changes: { from, to, insert: '' } }).newDoc.toString()
  }

  it('cancels stripping the whole body `> ` in place (no-op, box intact)', () => {
    expect(del(18, 20)).toBe(doc)
  })
  it('cancels deleting just the space (the `>body` corruption)', () => {
    expect(del(19, 20)).toBe(doc)
  })
  it('lets a JOIN through (merges the body up into the box)', () => {
    expect(del(17, 20)).toBe('> [!callout] headbody')
  })
  it('lets body content deletion through (prefix survives)', () => {
    expect(del(20, 24)).toBe('> [!callout] head\n> ')
  })
  it('lets the HEAD de-callout through (whole box removed on purpose)', () => {
    expect(del(0, 13)).toBe('head\n> body')
  })
})
