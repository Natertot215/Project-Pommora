import './widget.css'
import { useLayoutEffect, useRef, useState } from 'react'
import { GripHorizontal, GripVertical } from 'lucide-react'
import type { EditorView } from '@codemirror/view'
import type { Align, TableModel } from './model'
import { CellEditor } from './CellEditor'
import { cellToDisplay } from './codec'
import { nextCell, type NavDir } from './navigate'
import type { ConnectionsApi } from '../connections'

function alignClass(align: Align): string {
  return `mdpm-tbl-align-${align ?? 'left'}`
}

// Measured geometry of the rendered table — column x-spans (from the header cells) and visual-row y-spans
// (header + body). Re-measured on model change + table resize; drives the grips and the drag math.
interface Geom {
  cols: { left: number; width: number }[]
  rows: { top: number; height: number }[]
}

type Axis = 'col' | 'row'
// A live reorder drag. `from`/`to` are indices in the drag's axis (col 0..M-1; visual-row 1..N for body —
// row 0 = header, which never drags). `delta` is the subject's pixel offset, tracking the cursor.
interface Drag {
  axis: Axis
  from: number
  to: number
  delta: number
}

// During a column drag: the grabbed column follows the cursor (delta); columns between from and to slide
// by one column-width to open the gap. Mirror logic for rows. Returns the CSS transform for one cell/row.
function shift(drag: Drag | null, axis: Axis, index: number, size: number): string | undefined {
  if (!drag || drag.axis !== axis) return undefined
  const { from, to, delta } = drag
  const t = axis === 'col' ? 'translateX' : 'translateY'
  if (index === from) return `${t}(${delta}px)`
  if (to < from && index >= to && index < from) return `${t}(${size}px)`
  if (to > from && index > from && index <= to) return `${t}(${-size}px)`
  return undefined
}

// The slot the cursor sits over, along the axis (wrap-relative coordinate). Clamped to the axis bounds.
function slotAt(axis: Axis, geom: Geom, rel: number): number {
  const spans = axis === 'col' ? geom.cols : geom.rows
  for (let i = 0; i < spans.length; i++) {
    const s = axis === 'col' ? geom.cols[i].left + geom.cols[i].width : geom.rows[i].top + geom.rows[i].height
    if (rel < s) return i
  }
  return spans.length - 1
}

// The interactive table: dash-ratio columns (<colgroup> + table-layout:fixed); every cell is a live
// CellEditor. Hover grips ride a top gutter (columns) + left margin (rows); grabbing one reorders live.
export function TableView({
  model,
  onCellCommit,
  onExit,
  onReorder,
  connections
}: {
  model: TableModel
  onCellCommit: (row: number, col: number, text: string) => void
  onExit: (dir: 'before' | 'after') => void
  onReorder: (axis: Axis, from: number, to: number) => void
  connections?: () => ConnectionsApi | undefined
}): React.JSX.Element {
  const total = model.columns.reduce((sum, c) => sum + Math.max(1, c.dashes), 0) || model.columns.length
  const cells = useRef(new Map<string, EditorView>())
  const totalRows = model.rows.length + 1
  const cols = model.columns.length

  const wrapRef = useRef<HTMLDivElement>(null)
  const tableRef = useRef<HTMLTableElement>(null)
  const [geom, setGeom] = useState<Geom>({ cols: [], rows: [] })
  const [drag, setDrag] = useState<Drag | null>(null)

  useLayoutEffect(() => {
    const measure = (): void => {
      const table = tableRef.current
      const wrap = wrapRef.current
      if (!table || !wrap) return
      const w = wrap.getBoundingClientRect()
      const headerCells = table.tHead?.rows[0]?.cells
      const colGeom = headerCells
        ? Array.from(headerCells).map((c) => {
            const b = c.getBoundingClientRect()
            return { left: b.left - w.left, width: b.width }
          })
        : []
      const allRows = [...(table.tHead?.rows ?? []), ...(table.tBodies[0]?.rows ?? [])]
      const rowGeom = allRows.map((r) => {
        const b = r.getBoundingClientRect()
        return { top: b.top - w.top, height: b.height }
      })
      setGeom({ cols: colGeom, rows: rowGeom })
    }
    measure()
    const ro = new ResizeObserver(measure)
    if (tableRef.current) ro.observe(tableRef.current)
    return () => ro.disconnect()
  }, [model])

  // Grip pointer-down starts a live reorder. The subject follows the cursor; the target is the slot under
  // it; on release a changed target commits via onReorder (the widget rebuilds in the new order).
  const startDrag = (e: React.PointerEvent, axis: Axis, index: number): void => {
    if (axis === 'row' && index === 0) return // the header row never drags
    e.preventDefault()
    const wrap = wrapRef.current
    if (!wrap) return
    const box = wrap.getBoundingClientRect()
    const origin = axis === 'col' ? box.left : box.top
    const start = axis === 'col' ? e.clientX : e.clientY
    let current: Drag = { axis, from: index, to: index, delta: 0 }
    setDrag(current)
    const onMove = (ev: PointerEvent): void => {
      const pos = axis === 'col' ? ev.clientX : ev.clientY
      let to = slotAt(axis, geom, pos - origin)
      if (axis === 'row') to = Math.max(1, to) // can't drop a row above the header
      current = { axis, from: index, to, delta: pos - start }
      setDrag(current)
    }
    const onUp = (): void => {
      window.removeEventListener('pointermove', onMove)
      window.removeEventListener('pointerup', onUp)
      if (current.to !== current.from) onReorder(axis, current.from, current.to)
      else setDrag(null) // no move — snap back (a reorder rebuilds the widget, clearing this drag)
    }
    window.addEventListener('pointermove', onMove)
    window.addEventListener('pointerup', onUp)
  }

  const navigate = (row: number, col: number, dir: NavDir): void => {
    const target = nextCell(totalRows, cols, row, col, dir)
    if (target === 'before' || target === 'after') {
      onExit(target)
      return
    }
    const view = cells.current.get(`${target.row},${target.col}`)
    if (view) {
      view.focus()
      view.dispatch({ selection: { anchor: view.state.doc.length } }) // caret at end of the target cell
    }
  }

  const register =
    (row: number, col: number) =>
    (view: EditorView): (() => void) => {
      const key = `${row},${col}`
      cells.current.set(key, view)
      return () => cells.current.delete(key)
    }

  const cell = (row: number, col: number, text: string): React.JSX.Element => (
    <CellEditor
      initial={cellToDisplay(text)}
      connections={connections}
      onCommit={(t) => onCellCommit(row, col, t)}
      onNavigate={(dir) => navigate(row, col, dir)}
      register={register(row, col)}
    />
  )

  const colDragged = (ci: number): boolean => drag?.axis === 'col' && drag.from === ci
  const colW = (ci: number): number => geom.cols[ci]?.width ?? 0
  const rowH = (ri: number): number => geom.rows[ri]?.height ?? 0

  return (
    <div className={`mdpm-tbl-wrap${drag ? ' mdpm-tbl-dragging' : ''}`} ref={wrapRef}>
      <table className="mdpm-tbl" ref={tableRef}>
        <colgroup>
          {model.columns.map((c, i) => (
            <col key={i} style={{ width: `${(Math.max(1, c.dashes) / total) * 100}%` }} />
          ))}
        </colgroup>
        <thead>
          <tr>
            {model.header.map((text, ci) => (
              <th
                key={ci}
                className={`mdpm-tbl-cell ${alignClass(model.columns[ci]?.align ?? null)}${colDragged(ci) ? ' mdpm-tbl-subject' : ''}`}
                style={{ transform: shift(drag, 'col', ci, colW(ci)) }}
              >
                {cell(0, ci, text)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {model.rows.map((row, ri) => (
            <tr
              key={ri}
              className={drag?.axis === 'row' && drag.from === ri + 1 ? 'mdpm-tbl-subject' : ''}
              style={{ transform: shift(drag, 'row', ri + 1, rowH(ri + 1)) }}
            >
              {row.map((text, ci) => (
                <td
                  key={ci}
                  className={`mdpm-tbl-cell ${alignClass(model.columns[ci]?.align ?? null)}${colDragged(ci) ? ' mdpm-tbl-subject' : ''}`}
                  style={{ transform: shift(drag, 'col', ci, colW(ci)) }}
                >
                  {cell(ri + 1, ci, text)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
      {geom.cols.map((c, i) => (
        <div
          key={`col-${i}`}
          className="mdpm-tbl-grip-zone mdpm-tbl-grip-col"
          data-grip="col"
          data-index={i}
          style={{ left: c.left, width: c.width }}
          onPointerDown={(e) => startDrag(e, 'col', i)}
        >
          <GripHorizontal className="mdpm-tbl-grip" size={14} strokeWidth={2} />
        </div>
      ))}
      {geom.rows.map((r, j) => (
        <div
          key={`row-${j}`}
          className="mdpm-tbl-grip-zone mdpm-tbl-grip-row"
          data-grip="row"
          data-index={j}
          style={{ top: r.top, height: r.height }}
          onPointerDown={(e) => startDrag(e, 'row', j)}
        >
          <GripVertical className="mdpm-tbl-grip" size={14} strokeWidth={2} />
        </div>
      ))}
    </div>
  )
}
