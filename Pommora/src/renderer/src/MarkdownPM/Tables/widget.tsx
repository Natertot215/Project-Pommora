import { Decoration, type DecorationSet, EditorView, WidgetType } from '@codemirror/view'
import { docString } from '../editor/docCache'
import {
  Facet,
  StateField,
  StateEffect,
  type EditorState,
  type Extension,
  type Range,
  type Transaction,
} from '@codemirror/state'
import { undo, redo } from '@codemirror/commands'
import { createRoot, type Root } from 'react-dom/client'
import { tableRegions, modelFromRegion } from './regions'
import { parseDelimiter } from './codec'
import { cellCommitChange, structuralEditChange, tableSelfEdit } from './sync'
import { startBlockDrag } from '../editor/blockDrag'
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
  resizeColumn,
} from './operations'
import { tableMergeGuard } from './guard'
import type { TableModel } from './model'
import type { ConnectionsApi } from '../connections'
import type { TableMenuAction, TableMenuContext } from '@shared/tableMenu'

type ConnGetter = () => ConnectionsApi | undefined
// The connections getter reaches each cell's nested editor through a facet, so `[[…]]` render styled and
// drive autocomplete inside cells. toDOM reads it off the view at render time (no need to rebuild widgets).
const tableConnections = Facet.define<ConnGetter, ConnGetter>({
  combine: (vals) => vals[0] ?? (() => undefined),
})

// Heading-column UI state: the indices of this page's tables whose first column renders as a heading.
// A Pommora-only visual with no GFM equivalent, persisted to `.nexus/` by the host (see the load/save
// seam below + main/io/tableHeadingColumns). `setHeadingColsEffect` is the mount-time load (whole set);
// `toggleHeadingColEffect` is the menu action (one table index).
export interface TableHeadingColsApi {
  load: () => Promise<number[]>
  save: (indices: number[]) => void
}
const setHeadingColsEffect = StateEffect.define<number[]>()
const toggleHeadingColEffect = StateEffect.define<number>()

const headingColField = StateField.define<Set<number>>({
  create: () => new Set(),
  update(set, tr) {
    let next = set
    for (const e of tr.effects) {
      if (e.is(setHeadingColsEffect)) next = new Set(e.value)
      else if (e.is(toggleHeadingColEffect)) {
        next = new Set(next)
        if (next.has(e.value)) next.delete(e.value)
        else next.add(e.value)
      }
    }
    return next
  },
})

/** Re-apply a page's saved heading columns at mount (the widget reads the field when it builds). */
export function applySavedHeadingCols(view: EditorView, indices: number[]): void {
  if (indices.length === 0) return
  view.dispatch({ effects: setHeadingColsEffect.of(indices) })
}

// Cached after the first lazy import; parked on the DOM node so rebuilt widget instances can find it.
let TableViewComp: typeof import('./TableView').TableView | undefined
interface TableDom extends HTMLElement {
  _root?: Root
}

// A chosen table-menu action → a model transform. `index` is the column index (col/align actions) or the
// visual row index (row actions; body index = index - 1). `table:delete` is a doc-level region removal,
// handled by the caller, so it maps to null here.
function transformFor(
  action: TableMenuAction,
  index: number,
): ((m: TableModel) => TableModel) | null {
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
    case 'col:toggle-heading': // handled in onMenu (a .nexus/ toggle, not a source transform)
      return null
  }
}

class TableWidget extends WidgetType {
  private root: Root | undefined
  private destroyed = false

  constructor(
    readonly text: string,
    readonly model: TableModel,
    readonly tableIndex: number,
    readonly headingColumn: boolean,
  ) {
    super()
  }

  eq(other: TableWidget): boolean {
    return (
      other.text === this.text &&
      other.tableIndex === this.tableIndex &&
      other.headingColumn === this.headingColumn
    )
  }

  private renderInto(dom: TableDom, view: EditorView): void {
    const TV = TableViewComp
    if (!TV) return
    const commit = (row: number, col: number, text: string): void => {
      const change = cellCommitChange(docString(view.state.doc), this.tableIndex, row, col, text)
      if (change) view.dispatch({ changes: change, annotations: tableSelfEdit.of(true) })
    }
    // Navigating past a table edge moves the main caret before/after the table block.
    const exit = (dir: 'before' | 'after'): void => {
      const region = tableRegions(docString(view.state.doc))[this.tableIndex]
      if (!region) return
      view.dispatch({ selection: { anchor: dir === 'before' ? region.from : region.to } })
      view.focus()
    }
    const reorder = (axis: 'col' | 'row', from: number, to: number): boolean => {
      const change = structuralEditChange(docString(view.state.doc), this.tableIndex, (m) =>
        axis === 'col' ? moveColumn(m, from, to) : moveRow(m, from - 1, to - 1),
      )
      if (!change) return false // no-op (identical/empty columns) — nothing dispatched
      view.dispatch({ changes: change })
      return true
    }
    const resize = (boundaryIndex: number, dashDelta: number): boolean => {
      const change = structuralEditChange(docString(view.state.doc), this.tableIndex, (m) =>
        resizeColumn(m, boundaryIndex, dashDelta),
      )
      if (!change) return false // dashDelta clamped to a no-op — nothing dispatched
      view.dispatch({ changes: change })
      return true
    }
    // The heading-row action grip drags the whole table block (left-press → block drag; right-click → menu).
    const tableDrag = (e: PointerEvent): void => {
      const region = tableRegions(docString(view.state.doc))[this.tableIndex]
      if (region) startBlockDrag(view, e, { from: region.from, to: region.to })
    }
    const onMenu = (ctx: TableMenuContext): void => {
      void window.nexus.tableMenu(ctx).then((action) => {
        if (!action) return
        // Heading column is a `.nexus/`-persisted visual, not a source edit — toggle the field, which
        // rebuilds this table's widget (and the persist listener writes it to disk).
        if (action === 'col:toggle-heading') {
          view.dispatch({ effects: toggleHeadingColEffect.of(this.tableIndex) })
          return
        }
        const docText = docString(view.state.doc)
        const region = tableRegions(docText)[this.tableIndex]
        if (!region) return
        // Delete Table, or deleting the LAST column (deleting it would leave a 0-column table that no longer
        // parses) → remove the whole region. Every other action is a model transform over the region.
        if (
          action === 'table:delete' ||
          (action === 'col:delete' && modelFromRegion(region).columns.length <= 1)
        ) {
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
        headingColumn={this.headingColumn}
        onCellCommit={commit}
        onExit={exit}
        onReorder={reorder}
        onResize={resize}
        onMenu={onMenu}
        onTableDrag={tableDrag}
        onUndo={() => undo(view)}
        onRedo={() => redo(view)}
        connections={view.state.facet(tableConnections)}
      />,
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
  // `false` → undefined (not a throw) when the field isn't installed, e.g. in unit tests building a bare state.
  const headingCols = state.field(headingColField, false) ?? new Set<number>()
  const ranges: Range<Decoration>[] = []
  tableRegions(doc.toString()).forEach((region, i) => {
    const text = doc.sliceString(region.from, region.to)
    const model = modelFromRegion(region)
    ranges.push(
      Decoration.replace({
        widget: new TableWidget(text, model, i, headingCols.has(i)),
        block: true,
      }).range(region.from, region.to),
    )
  })
  return Decoration.set(ranges, true)
}

// A full rebuild re-decodes every table in the doc; skip it for edits that can't change any table —
// map the existing widgets forward instead. A table only changes when an edit touches its source, or
// when a delimiter row appears beside a changed range (the line that turns prose into a table).
function editAffectsTables(deco: DecorationSet, tr: Transaction): boolean {
  for (const it = deco.iter(); it.value; it.next()) {
    if (tr.changes.touchesRange(it.from, it.to) !== false) return true
  }
  const doc = tr.state.doc
  let delimiterNearby = false
  tr.changes.iterChangedRanges((_fromA, _toA, fromB, toB) => {
    if (delimiterNearby) return
    const first = doc.lineAt(fromB).number
    const last = doc.lineAt(toB).number
    for (let n = Math.max(1, first - 1); n <= Math.min(doc.lines, last + 1); n++) {
      if (parseDelimiter(doc.line(n).text)) {
        delimiterNearby = true
        return
      }
    }
  })
  return delimiterNearby
}

const widgetField = StateField.define<DecorationSet>({
  create: buildWidgetDecorations,
  update: (deco, tr) => {
    // Heading-column toggle: doc unchanged, so swap ONLY the toggled table's widget in place — but re-derive
    // text/model from the current doc, never off the old widget. Cell self-edits remap without rebuilding, so
    // a captured snapshot is stale after any edit; reusing it would render, then commit, pre-edit content.
    let next = deco
    let toggled = false
    for (const eff of tr.effects) {
      if (!eff.is(toggleHeadingColEffect)) continue
      toggled = true
      const idx = eff.value
      const on = tr.state.field(headingColField).has(idx)
      for (const cur = next.iter(); cur.value; cur.next()) {
        const w = cur.value.spec.widget
        if (w instanceof TableWidget && w.tableIndex === idx) {
          const region = tableRegions(docString(tr.state.doc))[idx]
          const text = region ? tr.state.doc.sliceString(region.from, region.to) : w.text
          const model = region ? modelFromRegion(region) : w.model
          next = next.update({
            filterFrom: cur.from,
            filterTo: cur.to,
            filter: () => false,
            add: [
              Decoration.replace({
                widget: new TableWidget(text, model, idx, on),
                block: true,
              }).range(cur.from, cur.to),
            ],
          })
          break
        }
      }
    }
    if (toggled) return next
    // Mount-time load applies the whole saved set at once → one full rebuild (fires once per page, not per toggle).
    if (tr.effects.some((e) => e.is(setHeadingColsEffect))) return buildWidgetDecorations(tr.state)
    // A cell commit edits one table's source. Map the widgets forward (keeps the focused cell editor
    // mounted), then rebuild THAT table's widget from the new doc so its model reflects the edit. Remapping
    // alone reuses the old widget instance, which CM keeps without re-rendering — leaving the static cells
    // (most visibly the just-edited cell once it demotes on navigation) drawing pre-edit text.
    if (tr.annotation(tableSelfEdit)) {
      let next = deco.map(tr.changes)
      const regions = tableRegions(docString(tr.state.doc))
      for (const cur = next.iter(); cur.value; cur.next()) {
        const w = cur.value.spec.widget
        if (!(w instanceof TableWidget)) continue
        const region = regions[w.tableIndex]
        if (!region) continue
        const text = tr.state.doc.sliceString(region.from, region.to)
        if (text === w.text) continue
        next = next.update({
          filterFrom: cur.from,
          filterTo: cur.to,
          filter: () => false,
          add: [
            Decoration.replace({
              widget: new TableWidget(text, modelFromRegion(region), w.tableIndex, w.headingColumn),
              block: true,
            }).range(cur.from, cur.to),
          ],
        })
        break
      }
      return next
    }
    if (!tr.docChanged) return deco
    return editAffectsTables(deco, tr) ? buildWidgetDecorations(tr.state) : deco.map(tr.changes)
  },
  provide: (f) => EditorView.decorations.from(f),
})

export function tableWidgetExtension(
  connections?: ConnGetter,
  onHeadingColsChange?: (indices: number[]) => void,
): Extension {
  // Persist a heading-column toggle (not the mount-time load) to `.nexus/` via the host seam.
  const persist = EditorView.updateListener.of((u) => {
    if (!u.transactions.some((tr) => tr.effects.some((e) => e.is(toggleHeadingColEffect)))) return
    onHeadingColsChange?.([...u.state.field(headingColField)])
  })
  // headingColField precedes widgetField so the widget reads the up-to-date set when it rebuilds.
  // atomicRanges over the table blocks: the main caret skips the table as one unit and a boundary
  // backspace/delete removes the whole block (undoable) instead of eating its pipes and breaking it.
  return [
    headingColField,
    widgetField,
    tableMergeGuard,
    EditorView.atomicRanges.of((view) => view.state.field(widgetField)),
    connections ? tableConnections.of(connections) : [],
    onHeadingColsChange ? persist : [],
  ]
}
