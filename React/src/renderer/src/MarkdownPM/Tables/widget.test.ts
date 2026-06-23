import { describe, it, expect } from 'vitest'
import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { EditorState } from '@codemirror/state'
import { buildWidgetDecorations } from './widget'
import { TableView } from './TableView'
import { parseTable } from './codec'

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

describe('table widget render (distinguishes the widget from the decoration grid)', () => {
  it('renders a real <table.mdpm-tbl> with dash-width <colgroup> + per-column alignment', () => {
    const model = parseTable('| Task | N |\n| :--- | ---: |\n| a | 1 |')!
    const html = renderToStaticMarkup(createElement(TableView, { model }))
    expect(html).toContain('<table class="mdpm-tbl">') // the decoration grid never creates a <table>
    expect(html).toContain('<colgroup>')
    expect(html).toMatch(/<col style="width:[\d.]+%/) // proportional dash-width columns
    expect(html).toContain('mdpm-tbl-align-left') // :--- → left
    expect(html).toContain('mdpm-tbl-align-right') // ---: → right
    expect(html).toContain('Task')
  })
})
