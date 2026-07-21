import { describe, it, expect } from 'vitest'
import { EditorState } from '@codemirror/state'
import { type DecorationSet, EditorView } from '@codemirror/view'
import { buildWidgetDecorations, tableWidgetExtension } from './widget'
import { cellCommitChange, tableSelfEdit } from './sync'
import type { TableModel } from './model'

const make = (doc: string): number => buildWidgetDecorations(EditorState.create({ doc })).size

// Reach the widget field's live decoration set (via the decorations facet) and return the first table
// widget's stored text + model — what TableView renders its static cells from.
function firstTableWidget(state: EditorState): { text: string; model: TableModel } {
  for (const provider of state.facet(EditorView.decorations)) {
    if (typeof provider === 'function') continue
    for (const it = (provider as DecorationSet).iter(); it.value; it.next()) {
      const w = it.value.spec.widget as unknown as { text: string; model: TableModel } | null
      if (w && 'model' in w) return w
    }
  }
  throw new Error('no table widget in decoration set')
}

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

  it('refreshes the widget model on a cell self-edit so static cells repaint live', () => {
    const doc = '| a | b |\n| --- | --- |\n| 1 | 2 |'
    const start = EditorState.create({ doc, extensions: [tableWidgetExtension()] })
    expect(firstTableWidget(start).model.rows[0][0]).toBe('1')

    const change = cellCommitChange(doc, 0, 1, 0, 'hello')
    expect(change).not.toBeNull()
    const next = start.update({
      changes: change ?? undefined,
      annotations: tableSelfEdit.of(true),
    }).state

    const w = firstTableWidget(next)
    expect(w.model.rows[0][0]).toBe('hello')
    expect(w.text).toContain('hello')
  })
})
