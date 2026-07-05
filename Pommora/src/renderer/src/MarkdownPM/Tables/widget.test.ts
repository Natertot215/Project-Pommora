import { describe, it, expect } from 'vitest'
import { EditorState } from '@codemirror/state'
import { buildWidgetDecorations } from './widget'

const make = (doc: string): number => buildWidgetDecorations(EditorState.create({ doc })).size

describe('table widget decorations', () => {
  it('emits one block-replace per valid table', () => {
    expect(make('| a | b |\n| --- | --- |\n| 1 | 2 |')).toBe(1)
  })

  it('emits none for a non-table document', () => {
    expect(make('just a paragraph\nand another line')).toBe(0)
  })

  it('emits one per table when several are present', () => {
    const two = '| a |\n| --- |\n| 1 |\n\ntext\n\n| x | y |\n| --- | --- |\n| 9 | 8 |'
    expect(make(two)).toBe(2)
  })

  it('covers the full table region (block range spans header through last row)', () => {
    const doc = 'lead\n\n| a | b |\n| --- | --- |\n| 1 | 2 |'
    const set = buildWidgetDecorations(EditorState.create({ doc }))
    let from = -1
    let to = -1
    set.between(0, doc.length, (f, t) => {
      from = f
      to = t
    })
    expect(doc.slice(from, to)).toBe('| a | b |\n| --- | --- |\n| 1 | 2 |')
  })
})
