import { Decoration, type DecorationSet, EditorView, WidgetType } from '@codemirror/view'
import { StateField, type EditorState, type Extension, type Range } from '@codemirror/state'
import { createRoot, type Root } from 'react-dom/client'
import { tableRegions } from './regions'
import { parseTable } from './codec'
import { cellCommitChange, tableSelfEdit } from './sync'
import type { TableModel } from './model'

// The table source stays in the document (canonical GFM); this block-replace renders an interactive HTML
// widget OVER it. `text` + `tableIndex` are the widget's identity. On a cell edit the widget re-locates its
// region by index in the live doc and dispatches a minimal, self-edit-annotated change, so the StateField
// remaps (rather than rebuilds) and the focused cell editor survives.
class TableWidget extends WidgetType {
  private root: Root | undefined
  private destroyed = false

  constructor(
    readonly text: string,
    readonly model: TableModel,
    readonly tableIndex: number
  ) {
    super()
  }

  eq(other: TableWidget): boolean {
    return other.text === this.text && other.tableIndex === this.tableIndex
  }

  toDOM(view: EditorView): HTMLElement {
    const dom = document.createElement('div')
    dom.className = 'mdpm-tbl-widget'
    const commit = (row: number, col: number, text: string): void => {
      const change = cellCommitChange(view.state.doc.toString(), this.tableIndex, row, col, text)
      if (change) view.dispatch({ changes: change, annotations: tableSelfEdit.of(true) })
    }
    // Navigating past a table edge moves the main caret before/after the table block.
    const exit = (dir: 'before' | 'after'): void => {
      const region = tableRegions(view.state.doc.toString())[this.tableIndex]
      if (!region) return
      view.dispatch({ selection: { anchor: dir === 'before' ? region.from : region.to } })
      view.focus()
    }
    // Lazy-load the React renderer: keeps this module unit-testable (the render chain pulls design-system
    // vanilla-extract that the test env can't build) and defers that cost until a table actually renders.
    void import('./TableView').then(({ TableView }) => {
      if (this.destroyed) return
      this.root = createRoot(dom)
      this.root.render(<TableView model={this.model} onCellCommit={commit} onExit={exit} />)
    })
    return dom
  }

  destroy(): void {
    this.destroyed = true
    // React forbids unmounting synchronously inside a render/commit; CM may destroy mid-update.
    const root = this.root
    this.root = undefined
    if (root) queueMicrotask(() => root.unmount())
  }

  ignoreEvent(): boolean {
    return true
  }
}

export function buildWidgetDecorations(state: EditorState): DecorationSet {
  const doc = state.doc
  const ranges: Range<Decoration>[] = []
  tableRegions(doc.toString()).forEach((region, i) => {
    const text = doc.sliceString(region.from, region.to)
    const model = parseTable(text)
    if (!model) return
    ranges.push(
      Decoration.replace({ widget: new TableWidget(text, model, i), block: true }).range(region.from, region.to)
    )
  })
  return Decoration.set(ranges, true)
}

const widgetField = StateField.define<DecorationSet>({
  create: buildWidgetDecorations,
  // Self-edit (the widget editing its own cell): remap the decorations so the widget + focused cell editor
  // stay mounted. External edits: rebuild from the doc. No doc change: keep.
  update: (deco, tr) =>
    tr.annotation(tableSelfEdit)
      ? deco.map(tr.changes)
      : tr.docChanged
        ? buildWidgetDecorations(tr.state)
        : deco,
  provide: (f) => EditorView.decorations.from(f)
})

export function tableWidgetExtension(): Extension {
  // atomicRanges over the table blocks: the main caret skips the table as one unit and a boundary
  // backspace/delete removes the whole block (undoable) instead of eating its pipes and breaking it.
  return [widgetField, EditorView.atomicRanges.of((view) => view.state.field(widgetField))]
}
