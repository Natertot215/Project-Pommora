import { EditorView, keymap } from '@codemirror/view'
import { Annotation, EditorState, Prec, RangeValue, RangeSet, type Extension } from '@codemirror/state'
import { tableRegions, type TableRegion } from './regions'

// Explicit structural operations (resize, add/delete row+column) annotate their transactions with this
// so they bypass the guard below. Keyboard edits never carry it, so they can never reshape a table.
export const StructuralEdit = Annotation.define<boolean>()

interface CellLoc {
  region: TableRegion
  row: number
  col: number
}

// ── The one structural rule ──────────────────────────────────────────────────────────────────────
// A table's "shape" is its column count, row count, and structural-pipe count — i.e. the syntax only.
// Any keyboard transaction that changes a table's shape is dropped wholesale; everything else (cell
// content, including emptying a cell) is freely editable. One rule covers typing, ranged deletes,
// paste, IME. Cell *content* collapsing to a zero-width `||` is fine — the renderer fills it in.
function shape(r: TableRegion): string {
  let pipes = 0
  for (const row of r.rows) pipes += row.pipes.length
  return `${r.delimiter.columns.length}:${r.rows.length}:${pipes}`
}
const structureGuard = EditorState.transactionFilter.of((tr) => {
  if (!tr.docChanged || tr.annotation(StructuralEdit)) return tr
  const before = tableRegions(tr.startState.doc.toString())
  if (before.length === 0) return tr
  const after = tableRegions(tr.newDoc.toString())
  for (const b of before) {
    const at = tr.changes.mapPos(b.from, 1)
    const a = after.find((r) => at >= r.from && at <= r.to)
    if (!a || shape(a) !== shape(b)) return [] // would reshape a table — cancel the transaction
  }
  return tr
})

// ── Atomic structure: caret skips hidden pipes + the delimiter line ──────────────────────────────
function structuralPairs(doc: string): [number, number][] {
  const pairs: [number, number][] = []
  for (const region of tableRegions(doc)) {
    for (const row of region.rows) for (const p of row.pipes) pairs.push([p, p + 1])
    pairs.push([region.delimiter.from, region.delimiter.to])
  }
  return pairs.sort((a, b) => a[0] - b[0])
}
class AtomicMarker extends RangeValue {}
const ATOMIC = new AtomicMarker()
const atomicStructure = EditorView.atomicRanges.of((view) =>
  RangeSet.of(structuralPairs(view.state.doc.toString()).map(([f, t]) => ATOMIC.range(f, t)), true)
)

// ── Cell-to-cell navigation ──────────────────────────────────────────────────────────────────────
function findCell(doc: string, pos: number): CellLoc | null {
  for (const region of tableRegions(doc)) {
    if (pos < region.from || pos > region.to) continue
    for (let row = 0; row < region.rows.length; row++) {
      const r = region.rows[row]
      if (pos < r.from || pos > r.to) continue
      const segs = r.segments
      for (let col = 0; col < segs.length; col++) if (pos <= segs[col][1]) return { region, row, col }
      return { region, row, col: Math.max(0, segs.length - 1) }
    }
  }
  return null
}

function caretFor(region: TableRegion, row: number, col: number): number {
  const r = region.rows[row]
  if (!r) return region.to
  const cell = r.cells[col]
  if (cell) return cell.to
  const seg = r.segments[col]
  return seg ? seg[1] : r.to
}

function moveTo(view: EditorView, pos: number): boolean {
  view.dispatch({ selection: { anchor: pos }, scrollIntoView: true })
  return true
}

// Tab / Shift-Tab / Enter move cell-to-cell and exit past the table's edges. We exit to the line
// below/above rather than parking the caret at the grid edge — a parked caret renders as a stray
// cursor element inside the grid, which the grid lays out as a phantom extra column.
function navigate(view: EditorView, dir: 'next' | 'prev' | 'down'): boolean {
  const s = view.state.selection.main
  if (!s.empty) return false
  const loc = findCell(view.state.doc.toString(), s.head)
  if (!loc) return false
  const { region, row, col } = loc
  const rows = region.rows.length
  const cols = region.delimiter.columns.length
  const doc = view.state.doc
  // Exit past the table edge. With no adjacent line (table at doc start/end) append a newline to exit
  // into — a user-gesture mutation the guard allows (the table's shape is unchanged).
  const exitDown = (): boolean => {
    const l = doc.lineAt(region.to)
    if (l.number < doc.lines) return moveTo(view, doc.line(l.number + 1).from)
    view.dispatch({ changes: { from: region.to, insert: '\n' }, selection: { anchor: region.to + 1 }, scrollIntoView: true })
    return true
  }
  const exitUp = (): boolean => {
    const l = doc.lineAt(region.from)
    if (l.number > 1) return moveTo(view, doc.line(l.number - 1).to)
    view.dispatch({ changes: { from: region.from, insert: '\n' }, selection: { anchor: region.from }, scrollIntoView: true })
    return true
  }
  if (dir === 'next') {
    if (col + 1 < cols) return moveTo(view, caretFor(region, row, col + 1))
    if (row + 1 < rows) return moveTo(view, caretFor(region, row + 1, 0))
    return exitDown()
  }
  if (dir === 'prev') {
    if (col > 0) return moveTo(view, caretFor(region, row, col - 1))
    if (row > 0) return moveTo(view, caretFor(region, row - 1, cols - 1))
    return exitUp()
  }
  if (row + 1 < rows) return moveTo(view, caretFor(region, row + 1, col))
  return exitDown()
}

// Shift+Enter is a no-op inside a table — in-cell line breaks are deferred to a dedicated multi-line-row
// feature (a single-cell <br> desyncs the row). Consumed so it can't reach a row-splitting newline.
function onShiftEnter(view: EditorView): boolean {
  const s = view.state.selection.main
  if (!s.empty) return false
  return findCell(view.state.doc.toString(), s.head) !== null
}

export function tableInput(): Extension {
  return [
    structureGuard,
    atomicStructure,
    Prec.highest(
      keymap.of([
        { key: 'Enter', run: (v) => navigate(v, 'down') },
        { key: 'Shift-Enter', run: onShiftEnter },
        { key: 'Tab', run: (v) => navigate(v, 'next') },
        { key: 'Shift-Tab', run: (v) => navigate(v, 'prev') }
      ])
    ),
    // Typing a pipe in a cell inserts the escaped form, so it adds content (literal `|`) not a column.
    Prec.highest(
      EditorView.inputHandler.of((view, from, to, text) => {
        if (text !== '|' || from !== to || !findCell(view.state.doc.toString(), from)) return false
        view.dispatch({ changes: { from, insert: '\\|' }, selection: { anchor: from + 2 }, userEvent: 'input' })
        return true
      })
    )
  ]
}
