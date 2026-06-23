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
// (header + body rows). Re-measured on model change + table resize; drives the absolutely-positioned grips.
interface Geom {
  cols: { left: number; width: number }[]
  rows: { top: number; height: number }[]
}

// The interactive table: dash-ratio columns (<colgroup> + table-layout:fixed); every cell is a live
// CellEditor. onCellCommit + navigation speak the visual-row convention — row 0 = header, row >= 1 = body.
// Hover grips ride a top gutter (columns) + left gutter (rows); they reveal only on gutter hover.
export function TableView({
  model,
  onCellCommit,
  onExit,
  connections
}: {
  model: TableModel
  onCellCommit: (row: number, col: number, text: string) => void
  onExit: (dir: 'before' | 'after') => void
  connections?: () => ConnectionsApi | undefined
}): React.JSX.Element {
  const total = model.columns.reduce((sum, c) => sum + Math.max(1, c.dashes), 0) || model.columns.length
  const cells = useRef(new Map<string, EditorView>())
  const totalRows = model.rows.length + 1
  const cols = model.columns.length

  const wrapRef = useRef<HTMLDivElement>(null)
  const tableRef = useRef<HTMLTableElement>(null)
  const [geom, setGeom] = useState<Geom>({ cols: [], rows: [] })

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

  return (
    <div className="mdpm-tbl-wrap" ref={wrapRef}>
      <table className="mdpm-tbl" ref={tableRef}>
        <colgroup>
          {model.columns.map((c, i) => (
            <col key={i} style={{ width: `${(Math.max(1, c.dashes) / total) * 100}%` }} />
          ))}
        </colgroup>
        <thead>
          <tr>
            {model.header.map((text, ci) => (
              <th key={ci} className={`mdpm-tbl-cell ${alignClass(model.columns[ci]?.align ?? null)}`}>
                {cell(0, ci, text)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {model.rows.map((row, ri) => (
            <tr key={ri}>
              {row.map((text, ci) => (
                <td key={ci} className={`mdpm-tbl-cell ${alignClass(model.columns[ci]?.align ?? null)}`}>
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
        >
          <GripVertical className="mdpm-tbl-grip" size={14} strokeWidth={2} />
        </div>
      ))}
    </div>
  )
}
