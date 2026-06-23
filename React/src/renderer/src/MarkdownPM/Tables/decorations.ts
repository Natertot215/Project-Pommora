import { Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate } from '@codemirror/view'
import { StateField, type EditorState, type Extension, type Range } from '@codemirror/state'
import { tableRegions } from './regions'

// display:none mark (not replace) so the pipe is excluded from grid layout — never steals a track.
const hidePipe = Decoration.mark({ class: 'md-table-pipe' })
const hideDelimLine = Decoration.replace({ block: true })

// Each row is a CSS grid with the SAME column template (one minmax(0,<dashes>fr) per column), so columns
// align across independent rows. Inline cell content is styled by the existing markdownDecorations plugin.
export function buildInline(doc: string): DecorationSet {
  const ranges: Range<Decoration>[] = []
  for (const region of tableRegions(doc)) {
    const template = region.delimiter.columns.map((c) => `minmax(0,${c.dashes}fr)`).join(' ')
    region.rows.forEach((row, ri) => {
      ranges.push(
        Decoration.line({
          class: ri === 0 ? 'md-table-row md-table-header' : 'md-table-row',
          attributes: { style: `grid-template-columns:${template}` }
        }).range(row.from)
      )
      for (const p of row.pipes) ranges.push(hidePipe.range(p, p + 1))
      row.segments.forEach(([from, to], ci) => {
        if (to <= from) return // zero-width foreign `||` cell — hardened in T9
        const align = region.delimiter.columns[ci]?.align ?? 'left'
        ranges.push(Decoration.mark({ class: `md-table-cell md-align-${align}` }).range(from, to))
      })
    })
  }
  return Decoration.set(ranges, true)
}

export function tableDecorations(): Extension {
  return ViewPlugin.fromClass(
    class {
      decorations: DecorationSet
      constructor(view: EditorView) {
        this.decorations = buildInline(view.state.doc.toString())
      }
      update(u: ViewUpdate): void {
        if (u.docChanged) this.decorations = buildInline(u.view.state.doc.toString())
      }
    },
    { decorations: (v) => v.decorations }
  )
}

// The delimiter row is removed as a whole block (line break + content). Block replaces must come
// from a StateField — a ViewPlugin can only touch inline/line geometry, not remove a line.
function buildDelim(state: EditorState): DecorationSet {
  const doc = state.doc
  const ranges: Range<Decoration>[] = []
  for (const region of tableRegions(doc.toString())) {
    const line = doc.lineAt(region.delimiter.from)
    if (line.number > 1) ranges.push(hideDelimLine.range(doc.line(line.number - 1).to, line.to))
  }
  return Decoration.set(ranges, true)
}

const delimiterField = StateField.define<DecorationSet>({
  create: buildDelim,
  update: (deco, tr) => (tr.docChanged ? buildDelim(tr.state) : deco),
  provide: (f) => EditorView.decorations.from(f)
})

export function tableDelimiterHider(): Extension {
  return delimiterField
}
