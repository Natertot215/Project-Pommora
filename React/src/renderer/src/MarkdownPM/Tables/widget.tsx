import { Decoration, type DecorationSet, EditorView, WidgetType } from '@codemirror/view'
import { Facet, StateField, type EditorState, type Extension, type Range } from '@codemirror/state'
import { undo, redo } from '@codemirror/commands'
import { createRoot, type Root } from 'react-dom/client'
import { tableRegions, modelFromRegion } from './regions'
import { cellCommitChange, structuralEditChange, tableSelfEdit } from './sync'
import {
  moveColumn,
  moveRow,
  setAlign,
  insertColumn,
  deleteColumn,
  insertRow,
  deleteRow,
  clearColumn,
  clearRow,
  resizeColumn
} from './operations'
import { tableMergeGuard } from './guard'
import type { TableModel } from './model'
import type { ConnectionsApi } from '../connections'
import type { TableMenuAction, TableMenuContext } from '@shared/tableMenu'

type ConnGetter = () => ConnectionsApi | undefined
// The connections getter reaches each cell's nested editor through a facet, so `[[…]]` render styled and
// drive autocomplete inside cells. toDOM reads it off the view at render time (no need to rebuild widgets).
const tableConnections = Facet.define<ConnGetter, ConnGetter>({
  combine: (vals) => vals[0] ?? (() => undefined)
})

// Cached after the first lazy import; parked on the DOM node so rebuilt widget instances can find it.
let TableViewComp: typeof import('./TableView').TableView | undefined
interface TableDom extends HTMLElement {
  _root?: Root
}

// A chosen table-menu action → a model transform. `index` is the column index (col/align actions) or the
// visual row index (row actions; body index = index - 1). `table:delete` is a doc-level region removal,
// handled by the caller, so it maps to null here.
function transformFor(action: TableMenuAction, index: number): ((m: TableModel) => TableModel) | null {
  switch (action) {
    case 'align:left':
      return (m) => setAlign(m, index, 'left')
    case 'align:center':
      return (m) => setAlign(m, index, 'center')
    case 'align:right':
      return (m) => setAlign(m, index, 'right')
    case 'col:insert-left':
      return (m) => insertColumn(m, index, 'left')
    case 'col:insert-right':
      return (m) => insertColumn(m, index, 'right')
    case 'col:clear':
      return (m) => clearColumn(m, index)
    case 'col:delete':
      return (m) => deleteColumn(m, index)
    case 'row:insert-above':
      return (m) => insertRow(m, index - 1, 'above')
    case 'row:insert-below':
      return (m) => insertRow(m, index - 1, 'below')
    case 'row:clear':
      return (m) => clearRow(m, index - 1)
    case 'row:delete':
      return (m) => deleteRow(m, index - 1)
    case 'table:delete':
      return null
  }
}

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

  private renderInto(dom: TableDom, view: EditorView): void {
    const TV = TableViewComp
    if (!TV) return
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
    const reorder = (axis: 'col' | 'row', from: number, to: number): boolean => {
      const change = structuralEditChange(view.state.doc.toString(), this.tableIndex, (m) =>
        axis === 'col' ? moveColumn(m, from, to) : moveRow(m, from - 1, to - 1)
      )
      if (!change) return false // no-op (identical/empty columns) — nothing dispatched
      view.dispatch({ changes: change })
      return true
    }
    const resize = (boundaryIndex: number, dashDelta: number): boolean => {
      const change = structuralEditChange(view.state.doc.toString(), this.tableIndex, (m) =>
        resizeColumn(m, boundaryIndex, dashDelta)
      )
      if (!change) return false // dashDelta clamped to a no-op — nothing dispatched
      view.dispatch({ changes: change })
      return true
    }
    const onMenu = (ctx: TableMenuContext): void => {
      void window.nexus.tableMenu(ctx).then((action) => {
        if (!action) return
        const docText = view.state.doc.toString()
        const region = tableRegions(docText)[this.tableIndex]
        if (!region) return
        // Delete Table, or deleting the LAST column (deleting it would leave a 0-column table that no longer
        // parses) → remove the whole region. Every other action is a model transform over the region.
        if (action === 'table:delete' || (action === 'col:delete' && modelFromRegion(region).columns.length <= 1)) {
          view.dispatch({ changes: { from: region.from, to: region.to, insert: '' } })
          return
        }
        const transform = transformFor(action, ctx.index)
        if (!transform) return
        const change = structuralEditChange(docText, this.tableIndex, transform)
        if (change) view.dispatch({ changes: change })
      })
    }
    let root = dom._root
    if (!root) {
      root = createRoot(dom)
      dom._root = root
    }
    this.root = root
    root.render(
      <TV
        model={this.model}
        onCellCommit={commit}
        onExit={exit}
        onReorder={reorder}
        onResize={resize}
        onMenu={onMenu}
        onUndo={() => undo(view)}
        onRedo={() => redo(view)}
        connections={view.state.facet(tableConnections)}
      />
    )
  }

  toDOM(view: EditorView): HTMLElement {
    const dom = document.createElement('div') as TableDom
    dom.className = 'mdpm-tbl-widget'
    // Lazy-import keeps this module unit-testable (render chain pulls design-system code the test env can't build).
    if (TableViewComp) {
      this.renderInto(dom, view)
    } else {
      void import('./TableView').then(({ TableView }) => {
        TableViewComp = TableView
        if (this.destroyed) return
        this.renderInto(dom, view)
      })
    }
    return dom
  }

  // Re-renders the existing React root in place (avoids CM destroy+recreate which re-mounts cell editors).
  // Returns false before the first async render has created the root — CM recreates in that case.
  updateDOM(dom: HTMLElement, view: EditorView): boolean {
    if (!TableViewComp || !(dom as TableDom)._root) return false
    this.renderInto(dom as TableDom, view)
    return true
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
    const model = modelFromRegion(region)
    ranges.push(
      Decoration.replace({ widget: new TableWidget(text, model, i), block: true }).range(region.from, region.to)
    )
  })
  return Decoration.set(ranges, true)
}

const widgetField = StateField.define<DecorationSet>({
  create: buildWidgetDecorations,
  update: (deco, tr) =>
    tr.annotation(tableSelfEdit)
      ? deco.map(tr.changes)
      : tr.docChanged
        ? buildWidgetDecorations(tr.state)
        : deco,
  provide: (f) => EditorView.decorations.from(f)
})

export function tableWidgetExtension(connections?: ConnGetter): Extension {
  // atomicRanges over the table blocks: the main caret skips the table as one unit and a boundary
  // backspace/delete removes the whole block (undoable) instead of eating its pipes and breaking it.
  return [
    widgetField,
    tableMergeGuard,
    EditorView.atomicRanges.of((view) => view.state.field(widgetField)),
    connections ? tableConnections.of(connections) : []
  ]
}
