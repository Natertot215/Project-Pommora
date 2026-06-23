import { describe, it, expect } from 'vitest'
import { EditorState } from '@codemirror/state'
import { tableInput, StructuralEdit } from './input'

const DOC = '| a | b |\n| --- | --- |\n| 1 | 2 |'
const make = (): EditorState => EditorState.create({ doc: DOC, extensions: [tableInput()] })

describe('tableInput structure guard', () => {
  it('blocks deleting a pipe', () => {
    expect(make().update({ changes: { from: 0, to: 1, insert: '' } }).state.doc.toString()).toBe(DOC)
  })

  it('blocks splitting a row with a newline', () => {
    expect(make().update({ changes: { from: 3, insert: '\n' } }).state.doc.toString()).toBe(DOC)
  })

  it('allows editing cell content', () => {
    expect(make().update({ changes: { from: 3, insert: 'x' } }).state.doc.toString()).toContain('| ax | b |')
  })

  it('allows clearing a cell (syntax intact — only the content empties)', () => {
    // delete the whole first cell content " a " — pipes/cols/rows unchanged, so it goes through
    expect(make().update({ changes: { from: 1, to: 4, insert: '' } }).state.doc.toString()).not.toBe(DOC)
  })

  it('lets an annotated structural edit through', () => {
    const next = make().update({
      changes: { from: 0, to: 1, insert: '' },
      annotations: StructuralEdit.of(true)
    }).state
    expect(next.doc.toString()).not.toBe(DOC)
  })
})
