import { describe, it, expect } from 'vitest'
import { EditorState } from '@codemirror/state'
import { fusedTableCount, tableMergeGuard } from './guard'

const t1 = '| A | B |\n| --- | --- |\n| 1 | 2 |'
const t2 = '| C | D |\n| --- | --- |\n| 3 | 4 |'

describe('fusedTableCount', () => {
  it('is 0 for a single well-formed table', () => {
    expect(fusedTableCount(t1)).toBe(0)
  })
  it('is 0 for two tables fenced by a blank line', () => {
    expect(fusedTableCount(`${t1}\n\n${t2}`)).toBe(0)
  })
  it('is 1 when two tables fuse with no blank line between them (second delimiter reads as body)', () => {
    expect(fusedTableCount(`${t1}\n${t2}`)).toBe(1)
  })
})

describe('tableMergeGuard — the transaction filter that refuses a fusing deletion', () => {
  const sep = `${t1}\n\n${t2}` // two tables fenced by a blank line
  const guarded = (doc: string): EditorState =>
    EditorState.create({ doc, extensions: [tableMergeGuard] })

  it('cancels deleting the blank line between two tables — the doc is left unchanged', () => {
    // remove one of the two separator newlines, which would fuse the tables
    const next = guarded(sep).update({ changes: { from: t1.length, to: t1.length + 1 } }).state
    expect(next.doc.toString()).toBe(sep)
  })

  it('allows a deletion that does not fuse tables', () => {
    const next = guarded(sep).update({ changes: { from: 2, to: 3 } }).state
    expect(next.doc.toString()).not.toBe(sep)
  })
})
